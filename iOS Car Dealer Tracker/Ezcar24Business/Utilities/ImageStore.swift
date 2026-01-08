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

extension Notification.Name {
    static let vehicleImageUpdated = Notification.Name("vehicleImageUpdated")
}

final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "image-store-io", qos: .utility)

    private init() {
        cache.countLimit = 200 // thumbnails are small; tweak as needed
    }

    // Directory URL for images
    private var directoryURL: URL {
        let fm = FileManager.default
        let baseDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = baseDir.appendingPathComponent("VehicleImages", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func imageURL(for id: UUID) -> URL { directoryURL.appendingPathComponent("\(id.uuidString).jpg") }

    // Save image data. We scale down large images and compress to JPEG to reduce IO and memory.
    func save(imageData: Data, for id: UUID, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) {
        // First clear old cache entry to ensure fresh image is displayed
        cache.removeObject(forKey: id.uuidString as NSString)

        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let url = self.imageURL(for: id)
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

    // Load UIImage with in-memory cache. Completion is called on the main thread.
    // Set forceReload to true to bypass cache and load fresh from disk.
    func load(id: UUID, forceReload: Bool = false, completion: @escaping (UIImage?) -> Void) {
        if !forceReload, let cached = cache.object(forKey: id.uuidString as NSString) {
            completion(cached)
            return
        }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let url = self.imageURL(for: id)
            var result: UIImage? = nil
            if let data = try? Data(contentsOf: url) { result = UIImage(data: data) }
            if let result { self.cache.setObject(result, forKey: id.uuidString as NSString) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // Clear cache for a specific vehicle (used when syncing from cloud)
    func clearCache(for id: UUID) {
        cache.removeObject(forKey: id.uuidString as NSString)
    }

    // Convenience SwiftUI Image loader (scaled for thumbnails)
    func swiftUIImage(id: UUID, completion: @escaping (Image?) -> Void) {
        load(id: id) { uiImage in
            if let uiImage {
                completion(Image(uiImage: uiImage))
            } else {
                completion(nil)
            }
        }
    }

    // Delete stored image and remove from cache
    func delete(id: UUID, completion: (() -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let url = self.imageURL(for: id)
            try? FileManager.default.removeItem(at: url)
            self.cache.removeObject(forKey: id.uuidString as NSString)
            DispatchQueue.main.async { completion?() }
        }
    }

    // Remove all images from disk and memory cache (used on sign-out/guest reset)
    func clearAll() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let dir = self.directoryURL
            if fm.fileExists(atPath: dir.path) {
                try? fm.removeItem(at: dir)
            }
            self.cache.removeAllObjects()
        }
    }


    // Check if image exists on disk (fast path without loading)
    func hasImage(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: imageURL(for: id).path)
    }

    // MARK: - Private
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
