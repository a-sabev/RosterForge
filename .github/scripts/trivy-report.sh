#!/usr/bin/env bash
# Renders a Trivy JSON report as markdown for the PR comment and the job summary.
# Usage: trivy-report.sh <trivy.json>   (env: COMMIT, TRIVY_VERSION, RUN_URL)
set -euo pipefail

report="$1"
max_packages=20

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
packages=$(jq '[.Results[]?.Vulnerabilities[]?.PkgName] | unique | length' "$report")

plural() { (( $1 == 1 )) && echo "$1 $2" || echo "$1 ${3:-$2s}"; }

# shields.io badge: green when zero, the severity colour otherwise.
badge() { # label count colour
  local colour=$3; (( $2 == 0 )) && colour=brightgreen
  echo "![$1: $2](https://img.shields.io/badge/${1// /%20}-$2-$colour?style=for-the-badge)"
}

# Marker lets the workflow find and update this comment instead of posting a new one.
echo '<!-- rosterforge-vulnerability-scan -->'

# GitHub alert box: the colour of the whole header follows the verdict.
if (( critical + high + secrets > 0 )); then
  echo '> [!CAUTION]'
  echo '> ### 🛡️ Security scan: action needed'
  parts=()
  (( critical > 0 )) && parts+=("**$critical critical**")
  (( high > 0 )) && parts+=("**$high high**")
  (( secrets > 0 )) && parts+=("**$(plural "$secrets" "committed secret")**")
  echo "> $(IFS=,; echo "${parts[*]}" | sed 's/,/ · /g') to fix before merging."
elif (( vulns + misconfigs > 0 )); then
  echo '> [!WARNING]'
  echo '> ### 🛡️ Security scan: worth a look'
  echo '> Nothing critical or high, but there are lower-severity findings below.'
else
  echo '> [!TIP]'
  echo '> ### 🛡️ Security scan: all clear'
  echo '> No known vulnerabilities in dependencies, no committed secrets, no misconfigurations. Ship it. 🚀'
fi

echo
echo "$(badge critical "$critical" critical) $(badge high "$high" orange) $(badge medium "$medium" yellow) $(badge low "$low" blue) $(badge secrets "$secrets" critical) $(badge config "$misconfigs" yellow)"

if (( vulns > 0 )); then
  echo
  echo "#### 📦 $(plural "$packages" "vulnerable dependency" "vulnerable dependencies")"
  echo
  # One collapsible card per package: worst severity first, then the version to upgrade to,
  # which is the highest fixed version on the installed major line across its CVEs.
  jq -r --argjson max "$max_packages" '
    def rank: {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}[.] // 4;
    def icon: ["🟥", "🟧", "🟨", "🟦", "⬜"][rank];
    def ver: split(".") | map(tonumber? // 0);
    def major: split(".")[0];
    def fix_for($installed):
      (split(", ") | map(select(. != ""))) as $all
      | (($all | map(select(major == ($installed | major)))) + $all) | first;
    def short_title: (. // "") | split(": ") | last | gsub("[\r\n]+"; " ")
      | if length > 100 then .[:97] + "…" else . end;

    [.Results[]?.Vulnerabilities[]?]
    | unique_by(.VulnerabilityID + .PkgName)
    | group_by(.PkgName)
    | map(.[0].InstalledVersion as $installed | {
        name: .[0].PkgName,
        installed: $installed,
        worst: (map(.Severity | rank) | min),
        target: (map(.FixedVersion // "" | fix_for($installed)) | map(select(. != null))
                 | sort_by(ver) | last),
        unfixed: any(.[]; (.FixedVersion // "") == ""),
        counts: (group_by(.Severity | rank) | map("\(length) \(.[0].Severity | ascii_downcase)")
                 | join(", ")),
        cves: sort_by(.Severity | rank)
      })
    | sort_by(.worst, -(.cves | length))
    | .[:$max][]
    | (.name | split(":")) as $id
    | "<details\(if .worst <= 1 then " open" else "" end)>",
      "<summary>\(.cves[0].Severity | icon) <b>\($id | last)</b> <code>\(.installed)</code>"
        + (if .target then " ➜ <code>\(.target)</code>" else " ➜ <i>no fix yet</i>" end)
        + " · \(.counts)</summary>",
      "",
      "<sub>\($id | first)</sub>",
      "",
      (.cves[] | "- \(.Severity | icon) [**\(.VulnerabilityID)**](\(.PrimaryURL
          // ("https://avd.aquasec.com/nvd/" + (.VulnerabilityID | ascii_downcase))))"
          + " \(.Title | short_title)"
          + (if (.FixedVersion // "") == "" then " · _no fix yet_" else "" end)),
      (if .unfixed and .target then "", "> Some of these have no fixed release yet." else empty end),
      "",
      "</details>",
      ""
  ' "$report"
  (( packages > max_packages )) && echo "_…and $((packages - max_packages)) more in the run summary._" && echo
fi

if (( secrets > 0 )); then
  echo
  echo '#### 🔑 Committed secrets'
  echo
  echo '> [!IMPORTANT]'
  echo '> Removing the line is not enough: rotate each secret, it is already in git history.'
  echo
  jq -r '.Results[]? | .Target as $file | .Secrets[]?
         | "- **\(.Title)** in `\($file)` line \(.StartLine)"' "$report"
fi

if (( misconfigs > 0 )); then
  echo
  echo '#### ⚙️ Configuration'
  echo
  jq -r '
    def icon: {"CRITICAL": "🟥", "HIGH": "🟧", "MEDIUM": "🟨", "LOW": "🟦"}[.] // "⬜";
    .Results[]? | .Target as $file | .Misconfigurations[]? | select(.Status == "FAIL")
    | "- \(.Severity | icon) **\(.Title)** in `\($file)` · \(.ID)"
      + (if .Resolution then "<br><sub>💡 \(.Resolution)</sub>" else "" end)' "$report"
fi

echo
echo '---'
commit=${COMMIT:-unknown}
footer="🔎 Trivy ${TRIVY_VERSION:-} · commit \`${commit::7}\`"
[ -n "${RUN_URL:-}" ] && footer+=" · [view run]($RUN_URL)"
echo "<sub>$footer · scans Maven dependencies, the Dockerfile, and committed secrets</sub>"
