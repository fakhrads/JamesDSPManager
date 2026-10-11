#!/system/bin/sh
if [ "$AIDL" = true ];then
MY_LIB="$MOD_VENDOR/lib64/soundfx/libjamesdsp.so"
ORIG_LIB="$MODPATH/tools/libjamesdsp-aidl.so"
PATCHELF="$MODPATH/tools/patchelf"
chmod +x "$PATCHELF"

# Start from the untouched lib so a previous boot's patching (or a firmware update) never sticks.
# cat keeps the target's inode and selinux label.
[ -f "$ORIG_LIB" ] && cat "$ORIG_LIB" > "$MY_LIB"

# The lib is loaded by the vendor effect HAL, so vendor/odm copies are what it links against
VENDOR_DIRS="/vendor/lib64 /odm/lib64"
OTHER_DIRS="/apex/*/lib64 /system/lib64"

lib_exists() {
	for DIR in $VENDOR_DIRS; do
		[ -f "$DIR/$1" ] && return 0
	done
	return 1
}

# highest version of $1 in the given dirs, version compared numerically
find_lib_version() {
	# shellcheck disable=SC3043
	local NAME="$1"; shift
	# shellcheck disable=SC2086
	find $* -maxdepth 1 -name "$NAME-V*-ndk.so" 2>/dev/null | sed 's|.*/||' | sort -t V -k 2 -n -u | tail -n 1
}

LIB_LIST="android.hardware.audio.effect android.media.audio.common.types android.hardware.common android.hardware.common.fmq"
	for LIB_NAME in $LIB_LIST; do
		CURRENT_NEEDED=$("$PATCHELF" --print-needed "$MY_LIB" | grep "^$LIB_NAME-V" | head -n 1)
		[ -z "$CURRENT_NEEDED" ] && continue
		if lib_exists "$CURRENT_NEEDED"; then
			echo " -- $CURRENT_NEEDED present in vendor, keeping it -- "
			continue
		fi
		# shellcheck disable=SC2086
		SYSTEM_AVAILABLE=$(find_lib_version "$LIB_NAME" $VENDOR_DIRS)
		# shellcheck disable=SC2086
		[ -z "$SYSTEM_AVAILABLE" ] && SYSTEM_AVAILABLE=$(find_lib_version "$LIB_NAME" $OTHER_DIRS)
		if [ -n "$SYSTEM_AVAILABLE" ] && [ "$CURRENT_NEEDED" != "$SYSTEM_AVAILABLE" ]; then
			"$PATCHELF" --replace-needed "$CURRENT_NEEDED" "$SYSTEM_AVAILABLE" "$MY_LIB"
			echo " -- Patched $LIB_NAME: $CURRENT_NEEDED -> $SYSTEM_AVAILABLE -- "
		fi
	done
	sync
fi
