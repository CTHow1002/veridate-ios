import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "VeriDate Admin",
  description: "Private verification review dashboard for VeriDate.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
