import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { isAuthenticated } from "@/lib/admin-session";

export default async function DashboardLayout({ children }: { children: ReactNode }) {
  if (!(await isAuthenticated())) {
    redirect("/login");
  }

  return children;
}
