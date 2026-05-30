import { ImageResponse } from "next/og";

export const alt =
  "MyContextProtocol — hosted MCP for SKILL.md repos";

export const size = { width: 1200, height: 630 };

export const contentType = "image/png";

/** 1200×630 Open Graph / Twitter large-card image (recommended aspect ~1.91:1). */
export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          paddingLeft: 72,
          paddingRight: 72,
          backgroundColor: "#0a0a0a",
          position: "relative",
        }}
      >
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundImage:
              "linear-gradient(135deg, #0a0a0a 0%, #171717 42%, #0c1829 100%)",
          }}
        />
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundImage:
              "radial-gradient(circle at 1px 1px, rgba(255,255,255,0.055) 1px, transparent 0)",
            backgroundSize: "28px 28px",
          }}
        />
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 20,
            position: "relative",
            zIndex: 1,
          }}
        >
          <div
            style={{
              fontSize: 62,
              fontWeight: 700,
              letterSpacing: -1.2,
              color: "#fafafa",
              lineHeight: 1.05,
            }}
          >
            MyContextProtocol
          </div>
          <div
            style={{
              fontSize: 30,
              fontWeight: 400,
              color: "rgba(250,250,250,0.78)",
              maxWidth: 920,
              lineHeight: 1.4,
            }}
          >
            Hosted MCP for SKILL.md repos — compile Git-backed skills into typed
            tools and resources.
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 14,
              marginTop: 28,
            }}
          >
            <div
              style={{
                width: 52,
                height: 4,
                borderRadius: 2,
                background: "linear-gradient(90deg, #2563eb, #60a5fa)",
              }}
            />
            <span
              style={{
                fontSize: 22,
                color: "#93c5fd",
                fontWeight: 600,
                letterSpacing: -0.3,
              }}
            >
              Model Context Protocol
            </span>
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
