const fallback = { version: "0.1.0", url: "https://github.com/lipefxo/notch-capture/releases/latest" };

type GitHubRelease = { tag_name?: string; html_url?: string };

export async function getLatestRelease() {
  try {
    const response = await fetch(
      "https://api.github.com/repos/lipefxo/notch-capture/releases/latest",
      {
        cache: "force-cache",
        headers: { Accept: "application/vnd.github+json" },
      },
    );
    if (!response.ok) return fallback;
    const release = (await response.json()) as GitHubRelease;
    return {
      version: release.tag_name?.replace(/^v/, "") || fallback.version,
      url: release.html_url || fallback.url,
    };
  } catch {
    return fallback;
  }
}
