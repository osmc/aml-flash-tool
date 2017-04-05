#!/bin/bash
#----------
target_out=
parts=
skip_uboot=
wipe=
reset=
m8=
linux=
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[m'

# Helper
# ------
show_help()
{
    echo "Usage      : $1 --target-out=<aosp output directory> --parts=<all|none|logo|recovery|boot|system> [--skip-uboot] [--wipe] [--reset=<y|n>] [--linux] [--m8]"
    echo "Example    : $1 --target-out=out/target/product/board"
    echo "Version    : 1.2"
    echo "Parameters : --target-out => Specify location path where are all the images to burn"
    echo "             --parts      => Specify which partitions to burn"
    echo "             --skip-uboot => Will not burn uboot"
    echo "             --wipe       => Destroy all partitions"
    echo "             --reset      => Force reset mode at the end of the burning"
    echo "             --m8         => For menson M8 chipsets like S805"
    echo "             --linux      => Specify the image to flash is linux not android"
}

# Check if a given file exists and exit if not
# --------------------------------------------
check_file()
{
    if [[ ! -f $1 ]]; then
        echo "$1 not found"
        exit 1
    fi
}

# Trap called on Ctrl-C
# ---------------------
cleanup()
{
    [[ -d $tmp_dir ]] && rm -rf "$tmp_dir"
    exit 1
}

# Wrapper for the Amlogic 'update' command
# ----------------------------------------
run_update()
{
    local cmd
    local ret=0

    cmd+="update 2>/dev/null"
    for arg in "$@"; do
        if [[ "$arg" =~ ' ' ]]; then
            cmd+=" \"$arg\""
        else
            cmd+=" $arg"
        fi
    done

    if `eval $cmd | grep -q "^ERR:"`; then
        [[ "$2" =~ reset|true ]] 
        #|| echo "$cmd: failed"
        ret=1
    fi

    return $ret
}

# Assert update wrapper
# ---------------------
run_update_assert()
{
    run_update "$@"
    if [[ $? != 0 ]]; then
        echo -e $RED"[KO]"
        exit 1
    fi
}

# Parse options
# -------------
for opt do
    optval="${opt#*=}"
    case "${opt%=*}" in
    --help|-h)
        show_help $(basename $0)
        exit 0
        ;;
    --target-out)
        target_out="$optval"
        ;;
    --parts)
        parts="$optval"
        ;;
    --skip-uboot)
        skip_uboot=1
        ;;
    --wipe)
        wipe=1
        ;;
    --reset)
        reset="$optval"
        ;;
    --m8)
        m8=1
        ;;
    --linux)
        linux=1
        ;;
    *)
        ;;
    esac
done

# Check parameters
# ----------------
if [[ -z $target_out ]]; then
    show_help
    exit 1
fi

if [[ ! -d $target_out ]]; then
    if [[ ! -f $target_out ]]; then
        echo "$target_out is not a directory"
        exit 1
    else
	target_img=$target_out
    fi 	    
fi

if [[ -z $parts ]]; then
    echo "Missing parts argument"
    exit 1
fi

which update &> /dev/null
if [[ $? != 0 ]]; then
    echo "'update' command not found"
    exit 1
fi

if ! `update identify | grep -iq firmware`; then
    echo "Amlogic device not found"
    exit 1
fi

trap cleanup SIGHUP SIGINT SIGTERM

# Create tmp directory
# --------------------
tmp_dir=$(mktemp -d /tmp/aml-XXXX)

# Unpack image if image is given
# ------------------------------
if [ ! -z "$target_img" ]; then
   aml_image_v2_packer -d $target_img $tmp_dir
   target_out=$tmp_dir
   find $tmp_dir -name '*.PARTITION' -exec sh -c 'mv "$1" "${1%.PARTITION}.img"' _ {} \;
   if [[ $m8 != 1 ]]; then
      mv $tmp_dir/_aml_dtb.img $tmp_dir/dtb.img 
   else
      mv $tmp_dir/meson.dtb $tmp_dir/dt.img
      mv $tmp_dir/UBOOT_COMP.USB $tmp_dir/u-boot-comp.bin
      mv $tmp_dir/DDR.USB $tmp_dir/ddr_init.bin
   fi
   mv $tmp_dir/bootloader.img $tmp_dir/u-boot.bin
   if [[ $linux = 1 ]]; then
      mv $tmp_dir/system.img $tmp_dir/rootfs.ext2.img2simg 
   fi
fi

# Uboot update 
# ------------
if [[ -z $skip_uboot ]]; then
    update_dir=$(dirname `which update`)
    if [[ $m8 != 1 ]]; then
        ddr=$update_dir/usbbl2runpara_ddrinit.bin
        fip=$update_dir/usbbl2runpara_runfipimg.bin
    else
        ddr=$target_out/ddr_init.bin
        fip=$update_dir/decompressPara_4M.dump
    fi
    uboot=$target_out/u-boot.bin
    if [[ $m8 != 1 ]]; then
        dtb=$target_out/dtb.img
    else
        dtb=$target_out/dt.img
    fi
    check_file "$uboot"
    check_file "$dtb"
    check_file "$ddr"
    check_file "$fip"
    uboot_size=$(stat -L -c %s "$uboot")

    if [[ $m8 != 1 ]]; then 
        bl2=$tmp_dir/u-boot.bl2
        tpl=$tmp_dir/u-boot.tpl
        dd if="$uboot" of="$bl2" bs=49152 count=1 &> /dev/null
        dd if="$uboot" of="$tpl" bs=49152 skip=1 &> /dev/null
    else
        check_file "$target_out/u-boot-comp.bin"
        tpl=$target_out/u-boot-comp.bin
    fi

    run_update bulkcmd "true"
    if [[ $? = 0 ]]; then
        echo -n "Rebooting board "
        run_update_assert bulkcmd "store rom_write 0x03000000 0 16"
        run_update bulkcmd "reset"
        for i in {1..8}
        do
            echo -n "."
            sleep 1
        done
    echo -e $GREEN"[OK]"$RESET
    fi

    echo -n "Initializing ddr "
    if [[ $m8 != 1 ]]; then
        run_update_assert cwr   "$bl2" 0xd9000000
        run_update_assert write "$ddr" 0xd900c000
        run_update_assert run          0xd9000000
    else
        run_update_assert cwr "$ddr"   0xd9000000
        run_update_assert run          0xd9000030
    fi
    for i in {1..8}
    do
        echo -n "."
        sleep 1
    done
    echo -e $GREEN"[OK]"$RESET

    echo -n "Running u-boot "
    if [[ $m8 != 1 ]]; then
        run_update_assert write "$bl2" 0xd9000000
        run_update_assert write "$fip" 0xd900c000 # tell bl2 to jump to tpl, aka u-boot
        run_update_assert write "$tpl" 0x0200c000
        run_update_assert run          0xd9000000
    else
        run_update_assert write "$fip" 0xd9010000
        run_update_assert write "$tpl" 0x00400000
        run_update_assert run          0xd9000030
        run_update_assert run          0x10000000
    fi
    for i in {1..8}
    do
        echo -n "."
        sleep 1
    done
    echo -e $GREEN"[OK]"$RESET
 
    if [[ $m8 != 1 ]]; then
        echo -n "Creating partitions "
        run_update_assert bulkcmd "disk_initial 0"
        echo -e $GREEN"[OK]"$RESET

	echo -n "Writing u-boot "
        run_update bulkcmd "store init 1"
	run_update bulkcmd "amlmmc rescan 1"
	run_update_assert write "$uboot" 0x03000000
        run_update_assert bulkcmd "store rom_write 0x03000000 0 $uboot_size"
        echo -e $GREEN"[OK]"$RESET

        echo -n "Writing device tree "
        run_update_assert write "$dtb" 0x03000000
        run_update_assert bulkcmd "store dtb write 0x03000000"
        echo -e $GREEN"[OK]"$RESET

        echo -n "Creating partitions "
        run_update_assert bulkcmd "disk_initial 0"
        run_update_assert bulkcmd "env default -a"
        run_update_assert bulkcmd "saveenv"
        echo -e $GREEN"[OK]"$RESET
    else
        echo -n "Creating partitions "
        if [[ $wipe = 1 ]]; then
            run_update_assert bulkcmd "disk_initial 3"
        else
            run_update_assert bulkcmd "disk_initial 0"
        fi
        echo -e $GREEN"[OK]"$RESET

        echo -n "Writing u-boot "
        run_update_assert partition bootloader "$uboot"
        echo -e $GREEN"[OK]"$RESET

        echo -n "Writing device tree "
        run_update_assert mwrite "$dtb" mem dtb normal
        echo -e $GREEN"[OK]"$RESET
    fi
fi

# Recovery partition update
# -------------------------
if [[ "$parts" =~ all|recovery ]] && [[ $linux != 1 ]]; then
    recovery=$target_out/recovery.img
    check_file "$recovery"

    echo -n "Writing recovery image "
    run_update_assert partition recovery "$recovery"
    echo -e $GREEN"[OK]"$RESET
fi

# Boot partition update
# ---------------------
if [[ "$parts" =~ all|boot ]]; then
    boot=$target_out/boot.img
    check_file "$boot"

    echo -n "Writing boot image "
    run_update_assert partition boot "$boot"
    echo -e $GREEN"[OK]"$RESET
fi

# System partition update
# -----------------------
if [[ "$parts" =~ all|system ]]; then
    if [[ $linux = 1 ]]; then
      system=$target_out/rootfs.ext2.img2simg
    else
      system=$target_out/system.img
    fi
    check_file "$system"

    echo -n "Writing system image "
    run_update_assert partition system "$system"
    echo -e $GREEN"[OK]"$RESET
fi

# Logo partition update
# ---------------------
if [[ "$parts" =~ all|logo ]]; then
    logo=$target_out/logo.img
    if [[ -f $logo ]]; then
        echo -n "Writing logo image "
        run_update_assert partition logo "$logo"
        echo -e $GREEN"[OK]"$RESET
    fi
fi

# Data and cache partitions wiping
# --------------------------------
if [[ $m8 != 1 ]] && [[ $linux != 1 ]]; then
    if [[ $wipe = 1 ]]; then
        echo -n "Wiping data partition "
        run_update_assert bulkcmd "amlmmc erase data"
        echo -e $GREEN"[OK]"$RESET
	
        echo -n "Wiping cache partition "
        run_update_assert bulkcmd "amlmmc erase cache"
        echo -e $GREEN"[OK]"$RESET

	echo -n "Writing cache image "
	cache=$target_out/cache.img
        if [[ ! -f $cache ]]; then
	  echo -e $YELLOW"[SKIP]"$RESET
        else
          run_update_assert partition cache "$cache"
          echo -e $GREEN"[OK]"$RESET
	fi
    fi
fi

# Terminate burning tool
# ----------------------
echo -n "Terminate update of the board "
run_update_assert bulkcmd save_setting
echo -e $GREEN"[OK]"$RESET

# Resetting board ? 
# -----------------
if [[ -z "$reset" ]]; then
    while true; do
        read -p "Do you want to reset the board? y/n [n]? " reset
        if [[ $reset =~ [yYnN] ]]; then
            break
        fi
    done
fi
if [[ $reset =~ [yY] ]]; then
    echo -n "Resetting board "
    run_update bulkcmd "burn_complete 1"
    echo -e $GREEN"[OK]"$RESET
fi
