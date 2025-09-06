import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(req: NextRequest) {
  const url = req.nextUrl;
  const isDashboard = url.pathname.startsWith("/dashboard");
  const hasSession =
    req.cookies.get("sb-access-token") ||
    req.cookies.get("supabase-auth-token");
  if (isDashboard && !hasSession) {
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

export const config = { matcher: ["/dashboard/:path*"] };
