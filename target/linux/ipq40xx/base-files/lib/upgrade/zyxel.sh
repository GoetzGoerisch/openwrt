#
# Copyright (C) 2016 lede-project.org
#
. /lib/functions.sh

zyxel_get_rootfs() {
	local rootfsdev

	if read cmdline < /proc/cmdline; then
		case "$cmdline" in
			*root=*)
				rootfsdev="${cmdline##*root=}"
				rootfsdev="${rootfsdev%% *}"
			;;
		esac

		echo "${rootfsdev}"
	fi
}

zyxel_do_upgrade() {
	local tar_file="$1"
	local board=$(board_name)
	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	case "$board" in
	zyxel,nbg6617)
		tar Oxf $tar_file ${board_dir}/kernel | mtd write - kernel

		if [ -n "$UPGRADE_BACKUP" ]; then
			tar Oxf $tar_file ${board_dir}/root | mtd -j "$UPGRADE_BACKUP" write - rootfs
		else
			tar Oxf $tar_file ${board_dir}/root | mtd write - rootfs
		fi
		;;
	zyxel,wsq50)
		# Identify our rootfs and kernel partitions
		local rootfs="$(zyxel_get_rootfs)"
		local kernel=

		[ -z "$rootfs" ] && echo "Upgrade failed: rootfs partition not found! Rebooting..." && reboot -f

		case "$rootfs" in
			"/dev/mmcblk0p5") # "rootfs"
				kernel=$(find_mmc_part "kernel")
			;;
			"/dev/mmcblk0p8") # "rootfs_1"
				kernel=$(find_mmc_part "kernel_1")
			;;
			*)
				echo "rootfs partition did not match expected value!"
			;;
		esac

		[ -z "$kernel" ] && echo "Upgrade failed: kernel partition not found! Rebooting..." && reboot -f

		# Flash both kernel and rootfs
		echo "Flashing kernel to $kernel"
		tar xf $tar_file ${board_dir}/kernel -O >"${kernel}"

		echo "Flashing rootfs to ${rootfs}"
		tar xf $tar_file ${board_dir}/root -O >"${rootfs}"

		EMMC_DATA_DEV="$(find_mmc_part rootfs_data)"
		if [ -n "$EMMC_DATA_DEV" ]; then
			if [ -n "$UPGRADE_BACKUP" ]; then
				emmc_copy_config
			else
				dd if=/dev/zero of="$EMMC_DATA_DEV" bs=512 count=8 2>/dev/null
			fi
		fi

		sync
		umount -a
		reboot -f
		;;
	*)
		echo "Unknown board ${board} - aborting"
		return 1
		;;
	esac


	return 0
}
