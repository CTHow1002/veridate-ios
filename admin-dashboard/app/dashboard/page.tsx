import { redirect } from "next/navigation";
import DashboardClient from "@/components/DashboardClient";
import { isAuthenticated } from "@/lib/admin-session";

export default async function DashboardPage() {
  if (!(await isAuthenticated())) {
    redirect("/login");
  }

  return <DashboardClient />;
}
