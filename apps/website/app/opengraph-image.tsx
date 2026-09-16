import { ImageResponse } from "next/og";

export const alt =
  "Tablet Notes. Keep the message with you. Now on the App Store.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          background: "#F7F3EA",
          color: "#222724",
          display: "flex",
          flexDirection: "column",
          padding: "64px 80px",
        }}
      >
        <div style={{ display: "flex", fontSize: 25, letterSpacing: 1 }}>
          TABLET NOTES
        </div>
        <div
          style={{
            display: "flex",
            fontSize: 90,
            lineHeight: 1.05,
            letterSpacing: -4,
            marginTop: 65,
          }}
        >
          Keep the message
        </div>
        <div
          style={{
            display: "flex",
            fontSize: 90,
            color: "#526B80",
            lineHeight: 1.05,
            letterSpacing: -4,
          }}
        >
          with you.
        </div>
        <div
          style={{
            display: "flex",
            fontSize: 22,
            marginTop: 50,
            color: "#526B80",
          }}
        >
          Now on the App Store · iPhone &amp; iPad
        </div>
      </div>
    ),
    size,
  );
}
