//
//  ImageStore.swift
//  Ezcar24Business
//
//  Lightweight image persistence + cache for vehicle photos.
//  Stores JPEGs under Documents/VehicleImages/<vehicle-id>.jpg
//  All disk IO and image processing are done off the main thread to keep UI responsive.
//

import Foundation
import SwiftUI
import UIKit
import ImageIO

extension Notification.Name {
    static let vehicleImageUpdated = Notification.Name("vehicleImageUpdated")
}

final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "image-store-io", qos: .utility)
    private let stateQueue = DispatchQueue(label: "image-store-state")
    private var activeDealerId: UUID?

    private init() {
        cache.countLimit = 200 // thumbnails are small; tweak as needed
    }

    // Directory URL for images
    private func directoryURL(dealerId: UUID?) -> URL {
        let fm = FileManager.default
        let baseDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dealerKey = dealerId?.uuidString ?? "guest"
        let dir = baseDir
            .appendingPathComponent("VehicleImages", isDirectory: true)
            .appendingPathComponent(dealerKey, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func photoDirectoryURL(dealerId: UUID?, vehicleId: UUID) -> URL {
        let base = directoryURL(dealerId: dealerId)
        let dir = base.appendingPathComponent(vehicleId.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func setActiveDealerId(_ id: UUID?) {
        stateQueue.sync {
            self.activeDealerId = id
        }
    }

    private func resolvedDealerId(_ dealerId: UUID?) -> UUID? {
        if let dealerId { return dealerId }
        var current: UUID?
        stateQueue.sync {
            current = activeDealerId
        }
        return current
    }

    func imageURL(for id: UUID, dealerId: UUID? = nil) -> URL {
        let resolved = resolvedDealerId(dealerId)
        return directoryURL(dealerId: resolved).appendingPathComponent("\(id.uuidString).jpg")
    }

    func photoURL(vehicleId: UUID, photoId: UUID, dealerId: UUID? = nil) -> URL {
        let resolved = resolvedDealerId(dealerId)
        return photoDirectoryURL(dealerId: resolved, vehicleId: vehicleId)
            .appendingPathComponent("\(photoId.uuidString).jpg")
    }

    // Save image data. We scale down large images and compress to JPEG to reduce IO and memory.
    func save(imageData: Data, for id: UUID, dealerId: UUID? = nil, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) {
        // First clear old cache entry to ensure fresh image is displayed
        cache.removeObject(forKey: id.uuidString as NSString)
        let url = imageURL(for: id, dealerId: dealerId)

        ioQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let dataToWrite = self.scaleAndCompress(imageData: imageData, maxDimension: maxDimension, quality: quality) ?? imageData
                try dataToWrite.write(to: url, options: .atomic)
                print("ImageStore: Saved image for vehicle \(id.uuidString) (\(dataToWrite.count) bytes)")
                if let uiImage = UIImage(data: dataToWrite) {
                    self.cache.setObject(uiImage, forKey: id.uuidString as NSString)
                }
                // Post notification that image was updated
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .vehicleImageUpdated, object: id)
                }
            } catch {
                print("ImageStore save error:", error)
            }
        }
    }

    func savePhoto(imageData: Data, vehicleId: UUID, photoId: UUID, dealerId: UUID? = nil, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) {
        cache.removeObject(forKey: photoId.uuidString as NSString)
        let url = photoURL(vehicleId: vehicleId, photoId: photoId, dealerId: dealerId)

        ioQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let dataToWrite = self.scaleAndCompress(imageData: imageData, maxDimension: maxDimension, quality: quality) ?? imageData
                try dataToWrite.write(to: url, options: .atomic)
                if let uiImage = UIImage(data: dataToWrite) {
                    self.cache.setObject(uiImage, forKey: photoId.uuidString as NSString)
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .vehicleImageUpdated, object: vehicleId)
                }
            } catch {
                print("ImageStore savePhoto error:", error)
            }
        }
    }

    // Load UIImage with in-memory cache. Completion is called on the main thread.
    // Set forceReload to true to bypass cache and load fresh from disk.
    func load(
        id: UUID,
        dealerId: UUID? = nil,
        targetSize: CGSize? = nil,
        forceReload: Bool = false,
        completion: @escaping (UIImage?) -> Void
    ) {
        let cacheKey = keyForCache(id: id.uuidString, targetSize: targetSize)
        if !forceReload, let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }
        let url = imageURL(for: id, dealerId: dealerId)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            var result: UIImage? = nil
            if let data = try? Data(contentsOf: url) {
                result = self.decodeImage(data: data, targetSize: targetSize)
            }
            if let result { self.cache.setObject(result, forKey: cacheKey) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func loadPhoto(
        vehicleId: UUID,
        photoId: UUID,
        dealerId: UUID? = nil,
        targetSize: CGSize? = nil,
        forceReload: Bool = false,
        completion: @escaping (UIImage?) -> Void
    ) {
        let cacheKey = keyForCache(id: photoId.uuidString, targetSize: targetSize)
        if !forceReload, let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }
        let url = photoURL(vehicleId: vehicleId, photoId: photoId, dealerId: dealerId)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            var result: UIImage? = nil
            if let data = try? Data(contentsOf: url) {
                result = self.decodeImage(data: data, targetSize: targetSize)
            }
            if let result { self.cache.setObject(result, forKey: cacheKey) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // Clear cache for a specific vehicle (used when syncing from cloud)
    func clearCache(for id: UUID) {
        cache.removeObject(forKey: id.uuidString as NSString)
    }

    // Convenience SwiftUI Image loader (scaled for thumbnails)
    func swiftUIImage(id: UUID, dealerId: UUID? = nil, targetSize: CGSize? = nil, completion: @escaping (Image?) -> Void) {
        load(id: id, dealerId: dealerId, targetSize: targetSize) { uiImage in
            if let uiImage {
                completion(Image(uiImage: uiImage))
            } else {
                completion(nil)
            }
        }
    }

    func swiftUIImagePhoto(
        vehicleId: UUID,
        photoId: UUID,
        dealerId: UUID? = nil,
        targetSize: CGSize? = nil,
        completion: @escaping (Image?) -> Void
    ) {
        loadPhoto(vehicleId: vehicleId, photoId: photoId, dealerId: dealerId, targetSize: targetSize) { uiImage in
            if let uiImage {
                completion(Image(uiImage: uiImage))
            } else {
                completion(nil)
            }
        }
    }

    // Delete stored image and remove from cache
    func delete(id: UUID, dealerId: UUID? = nil, completion: (() -> Void)? = nil) {
        let url = imageURL(for: id, dealerId: dealerId)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: url)
            self.cache.removeObject(forKey: id.uuidString as NSString)
            DispatchQueue.main.async { completion?() }
        }
    }

    func deletePhoto(vehicleId: UUID, photoId: UUID, dealerId: UUID? = nil, completion: (() -> Void)? = nil) {
        let url = photoURL(vehicleId: vehicleId, photoId: photoId, dealerId: dealerId)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: url)
            self.cache.removeObject(forKey: photoId.uuidString as NSString)
            DispatchQueue.main.async { completion?() }
        }
    }

    // Remove all images from disk and memory cache (used on sign-out/guest reset)
    func clearAll() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let baseDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
            let dir = baseDir.appendingPathComponent("VehicleImages", isDirectory: true)
            if fm.fileExists(atPath: dir.path) {
                try? fm.removeItem(at: dir)
            }
            self.cache.removeAllObjects()
        }
    }


    // Check if image exists on disk (fast path without loading)
    func hasImage(id: UUID, dealerId: UUID? = nil) -> Bool {
        FileManager.default.fileExists(atPath: imageURL(for: id, dealerId: dealerId).path)
    }

    func hasPhoto(vehicleId: UUID, photoId: UUID, dealerId: UUID? = nil) -> Bool {
        FileManager.default.fileExists(atPath: photoURL(vehicleId: vehicleId, photoId: photoId, dealerId: dealerId).path)
    }

    func normalizedJPEGData(imageData: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        scaleAndCompress(imageData: imageData, maxDimension: maxDimension, quality: quality)
    }

    // MARK: - Private
    private func keyForCache(id: String, targetSize: CGSize?) -> NSString {
        guard let targetSize else { return id as NSString }
        let width = Int(targetSize.width.rounded(.toNearestOrAwayFromZero))
        let height = Int(targetSize.height.rounded(.toNearestOrAwayFromZero))
        return "\(id)_\(width)x\(height)" as NSString
    }

    private func decodeImage(data: Data, targetSize: CGSize?) -> UIImage? {
        guard let targetSize, targetSize.width > 0, targetSize.height > 0 else {
            return UIImage(data: data)
        }
        let scale = UIScreen.main.scale
        let pixelSize = max(targetSize.width, targetSize.height) * scale
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(pixelSize)),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private func scaleAndCompress(imageData: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let uiImage = UIImage(data: imageData) else { return nil }
        let size = uiImage.size
        let maxSide = max(size.width, size.height)
        let scale = max(1, maxSide / maxDimension)
        let targetSize = CGSize(width: size.width / scale, height: size.height / scale)

        UIGraphicsBeginImageContextWithOptions(targetSize, true, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaled?.jpegData(compressionQuality: quality)
    }
}
