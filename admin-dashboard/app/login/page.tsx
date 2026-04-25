import { redirect } from "next/navigation";
import LoginForm from "@/components/LoginForm";
import { isAuthenticated } from "@/lib/admin-session";

export default async function LoginPage() {
  if (await isAuthenticated()) {
    redirect("/dashboard");
  }

  return (
    <main className="login-page">
      <section className="login-shell">
        <div className="login-panel">
          <p className="eyebrow">VeriDate Admin</p>
          <h1>Review verified dating submissions</h1>
          <LoginForm />
        </div>
      </section>
    </main>
  );
}
