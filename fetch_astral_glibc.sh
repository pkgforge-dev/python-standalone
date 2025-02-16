#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Produces: "/tmp/python-astral-glibc.tar"
## Self: https://raw.githubusercontent.com/pkgforge-dev/python-standalone/refs/heads/main/fetch_astral_glibc.sh
# PARALLEL_LIMIT="20" bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge-dev/python-standalone/refs/heads/main/fetch_astral_glibc.sh")
#-------------------------------------------------------#

#-------------------------------------------------------#
OUT_FILE="/tmp/python-astral-glibc.tar"
SRC_REPO="astral-sh/python-build-standalone"
 pushd "$(mktemp -d)" &>/dev/null && TMPDIR="$(realpath .)"
  #Fetch Release Metadata
   for i in {1..5}; do
     #gh api "repos/${SRC_REPO}/releases" --paginate | jq . > "${TMPDIR}/RELEASES.json" && break
     gh api "repos/${SRC_REPO}/releases" | jq . > "${TMPDIR}/RELEASES.json" && break
     echo "Retrying... ${i}/5"
     sleep 2
   done
  #Sanity Check URLs 
   REL_COUNT="$(jq -r '.. | objects | select(has("browser_download_url")) | .browser_download_url' "${TMPDIR}/RELEASES.json" | grep -iv 'null' | sort -u | wc -l | tr -d '[:space:]')"
   if [[ "${REL_COUNT}" -le 10 ]]; then
      echo -e "\n[-] FATAL: Failed to Fetch Release MetaData\n"
      echo "[-] Count: ${REL_COUNT}"
     exit 1
   else
    #Get Download URL
      REL_DL_URL="$(cat "${TMPDIR}/RELEASES.json" | jq -r '.[] | select(.prerelease | not) | .assets[].browser_download_url | select((. | test("\\.(sha|sha256|sha512|sig)$") | not) and (. | test("apple|darwin|macos|v2-|v3-|v4-|windows"; "i") | not))' |\
       grep -Ei "$(uname -m)" | grep -Ei "glibc|gnu" | grep -Ei "stripped" | sort --version-sort | tail -n 1 |\
       tr -d '[:space:]')"
   fi
  #Download
   if ! echo "${REL_DL_URL}" | grep -qiE '^https?://'; then
      echo -e "[-] FATAL: Failed to fetch Download URL"
     exit 1
   else
     curl -w "(DL) <== %{url}\n" -qfSL "${REL_DL_URL}" -o "${TMPDIR}/python.archive" | tee "${TMPDIR}/REL_NOTE.txt"
   fi
  #Extract
   if [[ -s "${TMPDIR}/python.archive" ]] && [[ $(stat -c%s "${TMPDIR}/python.archive") -gt 10000 ]]; then
     echo -e "[+] Downloaded Artifact"
     realpath "${TMPDIR}/python.archive" && du -sh "${TMPDIR}/python.archive"
    #Extract until Root
     mkdir -pv "${TMPDIR}/EXTRACT_DIR" && \
      COMMON_PREFIX="$(tar -tzf "${TMPDIR}/python.archive" | awk -F'/' '{if(NF>max_depth)max_depth=NF;paths[NR]=$0}END{split(paths[1],f,"/");for(i=1;i<=max_depth;i++){prefix=f[i];for(j in paths){split(paths[j],c,"/");if(c[i]!=prefix){print i-1;exit}}}print max_depth}' | tr -cd '0-9' | tr -d '[:space:]')"
      tar --strip-components="${COMMON_PREFIX}" -xvzf "${TMPDIR}/python.archive" -C "${TMPDIR}/EXTRACT_DIR"
    #Check
     if [[ ! -d "${TMPDIR}/EXTRACT_DIR" ]] || [[ "$(du -s "${TMPDIR}/EXTRACT_DIR" | cut -f1 | tr -d '[:space:]')" -le 1000 ]]; then
       echo -e "\n[-] FATAL: Extracted dir is empty\n"
      exit 1
     fi
    #Print as Tree 
     find -L "${TMPDIR}/EXTRACT_DIR" | sort | awk -F/ '{indent=""; for (i=2; i<NF; i++) indent=indent " "; print (NF>1 ? indent "--> " $NF : $NF)}'
    #Prep 
     sudo chown -R "$(whoami):$(whoami)" "${TMPDIR}/EXTRACT_DIR" && chmod -R 755 "${TMPDIR}/EXTRACT_DIR"
    #Repack
     rm -rf "${OUT_FILE}" 2>/dev/null
     pushd "${TMPDIR}/EXTRACT_DIR" &>/dev/null &&\
       7z a -ttar -mx="9" -mmt="$(($(nproc)+1))" -bsp1 -bt "${OUT_FILE}" "."
       realpath "${OUT_FILE}" && du -sh "${OUT_FILE}"
     pushd "${TMPDIR}" &>/dev/null
    #Gen Release Note
     if [[ -s "${OUT_FILE}" && $(stat -c%s "${OUT_FILE}") -gt 10000 ]]; then
       echo -e "" > "/tmp/RELEASE_NOTE.md"
       echo '---' >> "/tmp/RELEASE_NOTE.md"
       echo '```console' >> "/tmp/RELEASE_NOTE.md"
       echo -e "\n" >> "/tmp/RELEASE_NOTE.md"
       cat "${TMPDIR}/REL_NOTE.txt" >> "/tmp/RELEASE_NOTE.md"
       echo -e "\n[+] --> HOST" >> "/tmp/RELEASE_NOTE.md"
       echo "$(uname -m)-$(uname -s)-gnu" >> "/tmp/RELEASE_NOTE.md"
       echo -e "\n[+] --> FILE" >> "/tmp/RELEASE_NOTE.md"
       file "${OUT_FILE}" | sed 's|.*/||' >> "/tmp/RELEASE_NOTE.md"
       echo -e "\n[+] --> SIZE" >> "/tmp/RELEASE_NOTE.md"
       du -sh "${OUT_FILE}" | awk '{unit=substr($1,length($1)); sub(/[BKMGT]$/,"",$1); print $1 " " unit "B"}' >> "/tmp/RELEASE_NOTE.md"
       echo -e "\n[+] --> BLAKE3SUM" >> "/tmp/RELEASE_NOTE.md"
       b3sum "${OUT_FILE}" | grep -oE '^[a-f0-9]{64}' | tr -d '[:space:]' >> "/tmp/RELEASE_NOTE.md"
       echo -e "\n\n[+] --> SHA256SUM" >> "/tmp/RELEASE_NOTE.md"
       sha256sum "${OUT_FILE}" | grep -oE '^[a-f0-9]{64}' | tr -d '[:space:]' >> "/tmp/RELEASE_NOTE.md"
       echo -e "\n" >> "/tmp/RELEASE_NOTE.md"
       echo -e '```\n' >> "/tmp/RELEASE_NOTE.md"
    fi
   else
      echo -e "[-] FATAL: Downloaded Artifact is Probably Broken"
      echo -e "\n" && cat "${TMPDIR}/REL_NOTE.txt" ; echo -e "\n"
     exit 1
   fi
#-------------------------------------------------------#