import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { AuthProvider } from "@/lib/auth-context";
import { ApolloWrapper } from "@/lib/apollo-wrapper";
import { Sidebar } from "@/components/Sidebar";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "SignBridge Operator Portal",
  description: "Real-time emergency response for the deaf and hard-of-hearing",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <AuthProvider>
          <ApolloWrapper>
            <Sidebar />
            {/* Main content — offset by sidebar width on authed pages.
                The Sidebar renders null on /login so no offset needed there. */}
            <div className="sidebar-offset">
              {children}
            </div>
          </ApolloWrapper>
        </AuthProvider>
      </body>
    </html>
  );
}
