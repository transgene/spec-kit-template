#!/usr/bin/env bash
set -euo pipefail

_no_backup=0
if [ $# -eq 2 ] && [ "$1" = "--no-backup" ]; then
	_no_backup=1
	shift
elif [ $# -eq 2 ]; then
	echo "Usage: $0 [--no-backup] <target_directory>" >&2
	exit 1
elif [ $# -ne 1 ]; then
	echo "Usage: $0 [--no-backup] <target_directory>" >&2
	exit 1
fi

_target_dir="$1"

case "$_target_dir" in
/*) ;;
*)
	echo "ERROR: Target directory must be an absolute path. Got: $_target_dir" >&2
	exit 1
	;;
esac

_script_dir="$(cd "$(dirname "$0")" && pwd)"
_source_opencode="$_script_dir/src/.opencode"
_source_specify="$_script_dir/src/.specify"
_template="$_script_dir/sync-spec-kit.sh.tmpl"
_registry="$_script_dir/sync-spec-kit-registry.json"

for _d in "$_source_opencode" "$_source_specify"; do
	if [ ! -d "$_d" ]; then
		echo "ERROR: Source directory not found: $_d" >&2
		exit 1
	fi
done

if [ ! -f "$_template" ]; then
	echo "ERROR: Template not found: $_template" >&2
	exit 1
fi

if [ ! -f "$_registry" ]; then
	echo "ERROR: Registry not found: $_registry" >&2
	exit 1
fi

mkdir -p "$_target_dir"

_now=$(date '+%Y_%m_%d')
_report=()

_backup_file() {
	local filepath="$1"
	local dir filename backup_name backup_path n
	dir=$(dirname "$filepath")
	filename=$(basename "$filepath")

	backup_name="${filename}_bkp_${_now}"

	backup_path="$dir/$backup_name"
	n=1
	while [ -e "$backup_path" ]; do
		backup_name="${filename}_bkp_${_now}_$(printf '%02d' "$n")"
		backup_path="$dir/$backup_name"
		n=$((n + 1))
	done

	mv -- "$filepath" "$backup_path"
}

_copy_tree() {
	local src_root="$1"
	local dst_root="$2"
	local rel_dir
	while IFS= read -r -d '' rel_dir; do
		mkdir -p "$dst_root/$rel_dir"
	done < <(cd "$src_root" && find . -type d -print0 2>/dev/null)

	local rel_file
	while IFS= read -r -d '' rel_file; do
		rel_file="${rel_file#./}"
		local dst="$dst_root/$rel_file"

		if [ -f "$dst" ]; then
			if [ "$_no_backup" -eq 0 ]; then
				_backup_file "$dst"
				_report+=("$dst_root/$rel_file -> $(dirname "$dst")/$(basename "$dst")")
			else
				_report+=("$dst_root/$rel_file")
			fi
		fi

		cp -- "$src_root/$rel_file" "$dst"
	done < <(cd "$src_root" && find . -type f -print0 2>/dev/null)
}

_copy_tree "$_source_opencode" "$_target_dir/.opencode"
_copy_tree "$_source_specify" "$_target_dir/.specify"

cp -- "$_registry" "$_target_dir/sync-spec-kit-registry.json"

sed "s|__REPO_ROOT_PLACEHOLDER__|$_script_dir|g" "$_template" >"$_target_dir/sync-spec-kit.sh"
chmod +x "$_target_dir/sync-spec-kit.sh"

echo ""
echo "=== Provision Report ==="
if [ ${#_report[@]} -eq 0 ]; then
	echo "No files were overwritten."
else
	for _entry in "${_report[@]}"; do
		echo "$_entry"
	done
fi
echo "========================"
