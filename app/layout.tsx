import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });

export const metadata: Metadata = {
  metadataBase: new URL("https://www.tabletnotes.io"),
  title: "Tablet Notes — Keep the message with you.",
  description:
    "Record sermons, take timestamped notes, and revisit the message with transcripts, summaries, and AI Chat. Available now for iPhone and iPad.",
  openGraph: {
    title: "Tablet Notes — Keep the message with you.",
    description:
      "Your sermon recordings, notes, and reflections. Together in one place. Now on the App Store.",
    url: "https://www.tabletnotes.io",
    siteName: "Tablet Notes",
    type: "website",
  },
  twitter: { card: "summary_large_image" },
  appleWebApp: { title: "Tablet Notes" },
  itunes: { appId: "6748637379" },
};

export const viewport: Viewport = {
  themeColor: "#F7F3EA",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={inter.variable}>
      <head>
        <link rel="icon" type="image/png" href="/images/logomark-black.png" />
      </head>
      <body className="font-sans antialiased">{children}</body>
    </html>
  );
}
