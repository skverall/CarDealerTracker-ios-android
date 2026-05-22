import { NextResponse } from "next/server";
import { PNG } from "pngjs";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

function parsePngDataUrl(dataUrl: string): Buffer | null {
  const match = /^data:image\/png;base64,(.+)$/i.exec(dataUrl);
  if (!match) return null;
  return Buffer.from(match[1], "base64");
}

function flattenPng(bytes: Buffer): Buffer {
  const source = PNG.sync.read(bytes);
  const output = new PNG({ width: source.width, height: source.height });

  for (let i = 0; i < source.data.length; i += 4) {
    const alpha = source.data[i + 3] / 255;
    const inverseAlpha = 1 - alpha;

    output.data[i] = Math.round(source.data[i] * alpha + 255 * inverseAlpha);
    output.data[i + 1] = Math.round(source.data[i + 1] * alpha + 255 * inverseAlpha);
    output.data[i + 2] = Math.round(source.data[i + 2] * alpha + 255 * inverseAlpha);
    output.data[i + 3] = 255;
  }

  return PNG.sync.write(output, { colorType: 2 });
}

export async function POST(req: Request) {
  let body: { dataUrl?: string };
  try {
    body = (await req.json()) as { dataUrl?: string };
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON" }, { status: 400 });
  }

  if (!body?.dataUrl || typeof body.dataUrl !== "string") {
    return NextResponse.json({ ok: false, error: "Missing dataUrl" }, { status: 400 });
  }

  const input = parsePngDataUrl(body.dataUrl);
  if (!input) {
    return NextResponse.json({ ok: false, error: "Expected PNG data URL" }, { status: 400 });
  }

  try {
    const flattened = flattenPng(input);
    return NextResponse.json({
      ok: true,
      dataUrl: `data:image/png;base64,${flattened.toString("base64")}`,
    });
  } catch (e) {
    return NextResponse.json(
      { ok: false, error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}
