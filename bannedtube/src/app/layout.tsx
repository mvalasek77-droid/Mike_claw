import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "BannedTube - Where Banned Creators Speak Freely",
  description:
    "The uncensored video platform for creators banned from mainstream platforms.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-[var(--bg-primary)] text-[var(--text-primary)]">
        {children}
      </body>
    </html>
  );
}
