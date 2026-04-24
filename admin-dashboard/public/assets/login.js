const form = document.querySelector("#loginForm");
const error = document.querySelector("#loginError");

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  error.textContent = "";

  const formData = new FormData(form);
  const response = await fetch("/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      username: formData.get("username"),
      password: formData.get("password"),
    }),
  });

  const result = await response.json();
  if (!response.ok) {
    error.textContent = result.error || "Could not sign in.";
    return;
  }

  window.location.href = "/";
});
