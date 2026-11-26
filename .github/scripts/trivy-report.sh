#!/usr/bin/env bash
# Renders a Trivy JSON report as markdown for the PR comment and the job summary.
# Usage: trivy-report.sh <trivy.json>   (env: COMMIT, TRIVY_VERSION)
set -euo pipefail

report="$1"
max_rows=50

count() {
  jq "[.Results[]?.Vulnerabilities[]? | select(.Severity == \"$1\")]
      | unique_by(.VulnerabilityID + .PkgName) | length" "$report"
}
critical=$(count CRITICAL)
high=$(count HIGH)
medium=$(count MEDIUM)
low=$(count LOW)
secrets=$(jq '[.Results[]?.Secrets[]?] | length' "$report")
misconfigs=$(jq '[.Results[]?.Misconfigurations[]? | select(.Status == "FAIL")] | length' "$report")
vulns=$((critical + high + medium + low))

# Marker lets the workflow find and update this comment instead of posting a new one.
echo '<!-- rosterforge-vulnerability-scan -->'
if (( critical + high + secrets > 0 )); then
  echo '## 🔴 Vulnerability scan: action needed'
elif (( medium + low + misconfigs > 0 )); then
  echo '## 🟡 Vulnerability scan: findings to review'
else
  echo '## 🟢 Vulnerability scan: all clear'
fi

cat <<EOF

| 🟥 Critical | 🟧 High | 🟨 Medium | ⬜ Low | 🔑 Secrets | ⚙️ Misconfig |
|:---:|:---:|:---:|:---:|:---:|:---:|
| **$critical** | **$high** | **$medium** | **$low** | **$secrets** | **$misconfigs** |
EOF

if (( vulns > 0 )); then
  cat <<EOF

<details open><summary><b>Vulnerable dependencies</b> ($vulns)</summary>

| Severity | Package | Installed | Fixed in | ID | Title |
|---|---|---|---|---|---|
EOF
  jq -r --argjson max "$max_rows" '
    def rank: {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}[.] // 4;
    def icon: {"CRITICAL": "🟥", "HIGH": "🟧", "MEDIUM": "🟨", "LOW": "⬜"}[.] // "❔";
    def cell: tostring | gsub("[\r\n]+"; " ") | gsub("\\|"; "\\|");
    [.Results[]?.Vulnerabilities[]?]
    | unique_by(.VulnerabilityID + .PkgName)
    | sort_by((.Severity | rank), .PkgName)
    | .[:$max][]
    | "| \(.Severity | icon) \(.Severity | ascii_downcase) | `\(.PkgName)` | \(.InstalledVersion)"
      + " | \(.FixedVersion // "no fix yet" | cell)"
      + " | [\(.VulnerabilityID)](\(.PrimaryURL // ("https://avd.aquasec.com/nvd/" + (.VulnerabilityID | ascii_downcase))))"
      + " | \((.Title // "") | cell | .[:90]) |"
  ' "$report"
  (( vulns > max_rows )) && echo && echo "_Showing the $max_rows most severe of $vulns._"
  echo
  echo '</details>'
fi

if (( secrets > 0 )); then
  cat <<'EOF'

<details open><summary><b>Committed secrets</b></summary>

| File | Line | Rule |
|---|---:|---|
EOF
  jq -r '.Results[]? | .Target as $file | .Secrets[]?
         | "| `\($file)` | \(.StartLine) | \(.Title) |"' "$report"
  echo
  echo '</details>'
fi

if (( misconfigs > 0 )); then
  cat <<'EOF'

<details><summary><b>Misconfigurations</b></summary>

| Severity | File | ID | Issue |
|---|---|---|---|
EOF
  jq -r '.Results[]? | .Target as $file | .Misconfigurations[]? | select(.Status == "FAIL")
         | "| \(.Severity | ascii_downcase) | `\($file)` | \(.ID) | \(.Title) |"' "$report"
  echo
  echo '</details>'
fi

echo
echo "<sub>Trivy ${TRIVY_VERSION:-} · commit \`${COMMIT::7}\` · scans Maven dependencies, the Dockerfile, and committed secrets</sub>"
