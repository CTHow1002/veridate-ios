const list = document.querySelector("#submissionsList");
const template = document.querySelector("#submissionTemplate");
const summary = document.querySelector("#summaryText");
const banner = document.querySelector("#errorBanner");
const refreshButton = document.querySelector("#refreshButton");
const logoutButton = document.querySelector("#logoutButton");

refreshButton.addEventListener("click", loadSubmissions);
logoutButton.addEventListener("click", async () => {
  await fetch("/api/logout", { method: "POST" });
  window.location.href = "/login";
});

loadSubmissions();

async function loadSubmissions() {
  list.innerHTML = "";
  setBanner("");
  summary.textContent = "Loading pending reviews...";

  try {
    const response = await fetch("/api/submissions");
    const result = await response.json();

    if (response.status === 401) {
      window.location.href = "/login";
      return;
    }

    if (!response.ok) {
      throw new Error(result.error || "Could not load submissions.");
    }

    summary.textContent =
      result.submissions.length === 1
        ? "1 pending submission"
        : `${result.submissions.length} pending submissions`;

    if (result.submissions.length === 0) {
      list.innerHTML = `<div class="empty-state">No pending verification submissions.</div>`;
      return;
    }

    for (const submission of result.submissions) {
      list.appendChild(renderSubmission(submission));
    }
  } catch (error) {
    summary.textContent = "Could not load reviews.";
    setBanner(error.message);
  }
}

function renderSubmission(submission) {
  const node = template.content.firstElementChild.cloneNode(true);
  const profile = submission.profile || {};

  setText(node, "fullName", profile.full_name || "Unnamed user");
  setText(node, "submittedAt", formatDateTime(submission.submittedAt));
  setText(node, "dateOfBirth", profile.date_of_birth || "Not provided");
  setText(node, "work", joinParts([profile.job_title, profile.company_name]));
  setText(node, "education", joinParts([profile.education_level, profile.school_name]));

  for (const [key, file] of Object.entries(submission.files || {})) {
    const link = node.querySelector(`[data-file="${key}"]`);
    if (!link) continue;

    if (file?.url) {
      link.href = file.url;
      link.title = file.path || "";
    } else {
      link.removeAttribute("href");
      link.classList.add("missing-file");
      link.textContent = `${link.textContent} missing`;
    }
  }

  const approveButton = node.querySelector('[data-action="approve"]');
  const rejectButton = node.querySelector('[data-action="reject"]');
  const reasonInput = node.querySelector('[data-field="reason"]');
  const rowError = node.querySelector('[data-field="rowError"]');

  approveButton.addEventListener("click", () => reviewSubmission(submission.id, "approve", "", rowError));
  rejectButton.addEventListener("click", () => {
    reviewSubmission(submission.id, "reject", reasonInput.value, rowError);
  });

  return node;
}

async function reviewSubmission(id, action, rejectionReason, rowError) {
  rowError.textContent = "";

  try {
    const response = await fetch(`/api/submissions/${id}/${action}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ rejectionReason }),
    });
    const result = await response.json();

    if (!response.ok) {
      throw new Error(result.error || `Could not ${action} submission.`);
    }

    await loadSubmissions();
  } catch (error) {
    rowError.textContent = error.message;
  }
}

function setText(node, field, value) {
  node.querySelector(`[data-field="${field}"]`).textContent = value;
}

function setBanner(message) {
  banner.hidden = !message;
  banner.textContent = message;
}

function formatDateTime(value) {
  if (!value) return "Submitted date missing";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function joinParts(parts) {
  const text = parts.filter(Boolean).join(", ");
  return text || "Not provided";
}
