#!/bin/bash
#----------
target_img=
parts=
wipe=
reset=
soc=
efuse_file=
password=
destroy=
debug=0
update_return=
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[m'
TOOL_PATH="$(cd $(dirname $0); pwd)"

# Helper
# ------
show_help()
{
    echo "Usage      : $0 --img=/path/to/aml_upgrade_package.img> --parts=<all|none|bootloader|dtb|logo|recovery|boot|system|..> [--wipe] [--reset=<y|n>] [--soc=<m8|axg|gxl>] [efuse-file=/path/to/file/location] [--password=/path/to/password.bin]"
    echo "Version    : 4.0"
    echo "Parameters : --img        => Specify location path to aml_upgrade_package.img"
    echo "             --parts      => Specify which partition to burn"
    echo "             --wipe       => Destroy all partitions"
    echo "             --reset      => Force reset mode at the end of the burning"
    echo "             --soc        => Force soc type (gxl=S905/S912,axg=A113,m8=S805/A111)"
    echo "             --efuse-file => Force efuse OTP burn, use this option carefully "
    echo "             --password   => Unlock usb mode using password file provided"
    echo "             --destroy    => Erase the bootloader and reset the board"
}

# Check if a given file exists and exit if not
# --------------------------------------------
check_file()
{
    if [[ ! -f $1 ]]; then
        echo "$1 not found"
        cleanup
        exit 1
    fi
}

# Trap called on Ctrl-C
# ---------------------
cleanup()
{
    echo -e $RESET
    print_debug "Cleanup"
    [[ -d $tmp_dir ]] && rm -rf "$tmp_dir"
    exit 1
}

# Print debug function
# --------------------
print_debug()
{
   if [[ $debug == 1 ]]; then
      echo -e $YELLOW"$1"$RESET
   fi
}

# Wrapper for the Amlogic 'update' command
# ----------------------------------------
run_update_return()
{
    local cmd

    cmd+="$TOOL_PATH/tools/update 2>/dev/null"
    for arg in "$@"; do
        if [[ "$arg" =~ ' ' ]]; then
           cmd+=" \"$arg\""
        else
           cmd+=" $arg"
        fi
    done

    update_return=""
    print_debug "\nCommand ->$CYAN $cmd $RESET"
    update_return=`eval $cmd`
    print_debug "- Results ---------------------------------------------------"
    print_debug "$RED $update_return $RESET"
    print_debug "-------------------------------------------------------------"
    print_debug ""
    return 0
}

# Wrapper to the Amlogic 'update' command
# ---------------------------------------
run_update()
{
    local cmd
    local ret=0

    run_update_return "$@"

    if `echo $update_return | grep -q "ERR"`; then
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
       cleanup
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
    --img)
        target_img="$optval"
        ;;
    --parts)
        parts="$optval"
        ;;
    --wipe)
        wipe=1
        ;;
    --reset)
        reset="$optval"
        ;;
    --efuse-file)
        efuse_file="$optval"
        ;;
    --soc)
        soc="$optval"
        ;;
    --password)
        password="$optval"
        ;;
    --destroy)
        destroy=1
        ;;
    --debug)
        debug=1
        ;;
    *)
        ;;
    esac
done

# Check parameters
# ----------------
if [[ -z $destroy ]]; then
   if [[ -z $target_img ]]; then
      echo "Missing --img argument"
      show_help
      exit 1
   fi
   if [[ -z $parts ]]; then
      echo "Missing --parts argument"
      exit 1
   fi
fi
if [[ -z $soc ]]; then
   soc=gxl
fi
if [[ "$soc" != "gxl" ]] && [[ "$soc" != "axg" ]] && [[ "$soc" != "m8" ]]; then
   echo "Soc type is invalid, should be either gxl,axg,m8"
   exit 1
fi
run_update_return identify 7
if ! `echo $update_return | grep -iq firmware`; then
   echo "Amlogic device not found"
   exit 1
fi

# Set trap
# --------
trap cleanup SIGHUP SIGINT SIGTERM

# Check if the board is locked with a password
# --------------------------------------------
need_password=0
run_update_return identify 7
if `echo $update_return | grep -iq "Password check NG"`; then
   need_password=1
fi
if [[ $need_password == 1 ]]; then
   if [[ -z $password ]]; then
     echo "The board is locked with a password, please provide a password using --password option !"
     exit 1
   fi
fi

# Unlock usb mode by password
# ---------------------------
if [[ $need_password == 1 ]]; then
   if [[ $password != "" ]]; then
      echo -n "Unlocking usb interface "
      run_update_assert password $password
      run_update_return identify 7
      if `echo $update_return | grep -iq "Password check OK"`; then
         echo -e $GREEN"[OK]"$RESET
      else
         echo -e $RED"[KO]"$RESET
         echo "It seems you provided an incorrect password !"
         exit 1
      fi
   fi
fi

# Create tmp directory
# --------------------
tmp_dir=$(mktemp -d /tmp/aml-flash-tool-XXXX)

# Should we destroy the boot ?
# ----------------------------
if [[ "$parts" == "all" ]] || [[ "$parts" == "bootloader" ]] || [[ "$parts" == "" ]] || [[ "$parts" == "none" ]]; then
   run_update tplcmd "echo 12345"
   run_update bulkcmd "low_power"
   if [[ $? = 0 ]]; then
      echo -n "Rebooting the board "
      run_update bulkcmd "bootloader_is_old"
      # Actually this command don't really erase the bootloader, it reboot to prepare update
      run_update_assert bulkcmd "erase_bootloader"
      if [[ $destroy == 1 ]]; then
        run_update bulkcmd "store erase boot"
        run_update bulkcmd "amlmmc erase 1"
      fi
      run_update bulkcmd "reset"
      if [[ $destroy == 1 ]]; then
        echo -e $GREEN"[OK]"$RESET
        exit 0
      fi
      for i in {1..8}
         do
         echo -n "."
         sleep 1
      done
      echo -e $GREEN"[OK]"$RESET
   else
     if [[ $destroy == 1 ]]; then
        echo "Seems board is already in usb mode, nothing to do more..."
        exit 0
     fi
   fi
fi
if [[ $destroy == 1 ]]; then
   exit 0
fi

# Unlock usb mode by password
# ---------------------------
# If we started with usb mode from uboot, the password is already unlocked
# But just after we reset the board, then fall into rom mode
# That's why we need to recheck password lock a second time
need_password=0
run_update_return identify 7
if `echo $update_return | grep -iq "Password check NG"`; then
   need_password=1
fi
if [[ $need_password == 1 ]]; then
   if [[ -z $password ]]; then
     echo "The board is locked with a password, please provide a password using --password option !"
     exit 1
   fi
fi
if [[ $need_password == 1 ]]; then
   if [[ $password != "" ]]; then
      echo -n "Unlocking usb interface "
      run_update_assert password $password
      run_update_return identify 7
      if `echo $update_return | grep -iq "Password check OK"`; then
         echo -e $GREEN"[OK]"$RESET
      else
         echo -e $RED"[KO]"$RESET
         echo "It seems you provided an incorrect password !"
         exit 1
      fi
   fi
fi

# Read chip id
# ------------
#if [[ "$soc" == "auto" ]]; then
#  echo -n "Identify chipset type "
#  value=`$TOOL_PATH/tools/update chipid|grep ChipID|cut -d ':' -f2|xxd -r -p|cut -c1-6`
#  echo $value
#  if [[ "$value" == "AMLGXL" ]]; then
#     soc=gxl
#  fi
#  if [[ "$value" == "AMLAXG" ]]; then
#     soc=axg
#  fi
#  if [[ "$soc" != "gxl" ]] && [[ "$soc" != "axg" ]] && [[ "$soc" != "m8" ]]; then
#     echo -e $RED"[KO]"$RESET
#     echo "Unable to identify chipset, Try by forcing it manually with --soc=<gxl,axg,m8>"
#     exit 1
#  else
#     echo -e $GREEN"["$value"]"$RESET
#  fi
#fi

# Check if board is secure
# ------------------------
secured=0
value=0
if [[ "$soc" == "gxl" ]]; then
   run_update_return rreg 4 0xc8100228
   value=0x`echo $update_return|awk -F: '{gsub(/ /,"",$2);print $2}'`
   print_debug "0xc8100228      = $value"
   value=$(($value & 0x10))
   print_debug "Secure boot bit = $value"
   fi
if [[ "$soc" == "axg" ]]; then
   run_update_return rreg 4 0xff800228
   value=0x`echo $update_return|awk -F: '{gsub(/ /,"",$2);print $2}'`
   print_debug "0xff800228      = $value"
   value=$(($value & 0x10))
   print_debug "Secure boot bit = $value"
fi
if [[ $value != 0 ]]; then
   secured=1
   echo "Board is in secure mode"
fi

# Unpack image if image is given
# ------------------------------
$TOOL_PATH/tools/aml_image_v2_packer -d $target_img $tmp_dir &>/dev/null
print_debug ""
print_debug "Parsing image configuration files"
print_debug "---------------------------------"
platform_conf_name=`awk '/sub_type=\"platform\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "platform_conf_name  = $platform_conf_name"
ddr_filename=`awk '/sub_type=\"DDR\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "ddr_filename        = $ddr_filename"
uboot_filename=`awk '/sub_type=\"UBOOT\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "uboot_filename      = $uboot_filename"
uboot_comp_filename=`awk '/sub_type=\"UBOOT_COMP\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "uboot_comp_filename = $uboot_comp_filename"
dtb_meson_filename=`awk '/sub_type=\"meson\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "dtb_meson_filename  = $dtb_meson_filename"
dtb_meson1_filename=`awk '/sub_type=\"meson1\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "dtb_meson1_filename = $dtb_meson1_filename"
ddr_enc_filename=`awk '/sub_type=\"DDR_ENC\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "ddr_enc_filename    = $ddr_enc_filename"
uboot_enc_filename=`awk '/sub_type=\"UBOOT_ENC\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "uboot_enc_filename  = $uboot_enc_filename"
keys_filename=`awk '/sub_type=\"keys\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg`
print_debug "keys_filename       = $keys_filename"
platform=`awk '/Platform:/{gsub("Platform:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "platform            = $platform"
bin_params=`awk '/BinPara:/{gsub("BinPara:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "bin_params          = $bin_params"
ddr_load=`awk '/DDRLoad:/{gsub("DDRLoad:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "ddr_load            = $ddr_load"
ddr_run=`awk '/DDRRun:/{gsub("DDRRun:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "ddr_run             = $ddr_run"
uboot_down=`awk '/Uboot_down:/{gsub("Uboot_down:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "uboot_down          = $uboot_down"
uboot_decomp=`awk '/Uboot_decomp:/{gsub("Uboot_decomp:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "uboot_decomp        = $uboot_decomp"
uboot_enc_down=`awk '/Uboot_enc_down:/{gsub("Uboot_enc_down:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "uboot_enc_down      = $uboot_enc_down"
uboot_enc_run=`awk '/Uboot_enc_run:/{gsub("Uboot_enc_run:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "uboot_enc_run       = $uboot_enc_run"
uboot_load=`awk '/UbootLoad:/{gsub("UbootLoad:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "uboot_load          = $uboot_load"
uboot_run=`awk '/UbootRun:/{gsub("UbootRun:","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "uboot_run           = $uboot_run"
bl2_params=`awk '/bl2ParaAddr=/{gsub("bl2ParaAddr=","",$1); print $1}' $tmp_dir/$platform_conf_name`
print_debug "bl2_params          = $bl2_params"
nb_partitions=`awk '/main_type=\"PARTITION\"/{print}' $tmp_dir/image.cfg|wc -l`
print_debug "nb_partitions       = $nb_partitions"
partitions_file=( `awk '/main_type=\"PARTITION\"/{gsub("file=","",$1); gsub(/"/,"",$1); print $1}' $tmp_dir/image.cfg | xargs` )
partitions_name=( `awk '/main_type=\"PARTITION\"/{gsub("sub_type=","",$3); gsub(/"/,"",$3); print $3}' $tmp_dir/image.cfg | xargs` )
partitions_type=( `awk '/main_type=\"PARTITION\"/{gsub("file_type=","",$4); gsub(/"/,"",$4); print $4}' $tmp_dir/image.cfg | xargs` )
print_debug ""
print_debug "Partition list"
print_debug "--------------"
for i in $(seq 0 `expr $nb_partitions - 1`)
do
  print_debug "$i ${partitions_file[$i]} ${partitions_name[$i]} ${partitions_type[$i]}" 
done
print_debug ""

# Bootloader update
# -----------------
if [[ "$parts" == "all" ]] || [[ "$parts" == "bootloader" ]]; then
   if [[ $soc == "gxl" ]] || [[ $soc == "axg" ]]; then
      ddr=$TOOL_PATH/tools/usbbl2runpara_ddrinit.bin
      fip=$TOOL_PATH/tools/usbbl2runpara_runfipimg.bin
   fi
   if [[ $soc == "m8" ]]; then
      ddr=$tmp_dir/$ddr_filename
      fip=$TOOL_PATH/tools/decompressPara_4M.dump
   fi

   for i in $(seq 0 `expr $nb_partitions - 1`)
   do
   if [[ "${partitions_name[$i]}" == "bootloader" ]]; then
      bootloader_file=$tmp_dir/${partitions_file[$i]}
      break
   fi
   done
   if [[ $soc == "gxl" ]] || [[ $soc == "axg" ]]; then
      for i in $(seq 0 `expr $nb_partitions - 1`)
      do
      if [[ "${partitions_name[$i]}" == "_aml_dtb" ]]; then
         dtb_file=$tmp_dir/${partitions_file[$i]}
         break
      fi
      done
   fi
   if [[ $soc == "m8" ]]; then
      dtb_file=$tmp_dir/$dtb_meson_filename
   fi

   print_debug "Bootloader/DTB files"
   print_debug "--------------------"
   print_debug "bootloader_file = $bootloader_file"
   print_debug "dtb_file        = $dtb_file"
   print_debug ""

   check_file "$bootloader_file"
   check_file "$dtb_file"
   check_file "$ddr"
   check_file "$fip"

   if [[ $soc == "gxl" ]] || [[ $soc == "axg" ]]; then
      if [[ $secured == 0 ]]; then
         bl2=$tmp_dir/$ddr_filename
         tpl=$tmp_dir/$uboot_filename
      else
         bl2=$tmp_dir/$ddr_enc_filename
         tpl=$tmp_dir/$uboot_enc_filename
         if [[ -z "$ddr_enc_filename" ]] || [[ -z "$uboot_enc_filename" ]]; then
           echo "Your board is secured but the image you want to flash does not contain any signed bootloader !"
           echo "Please check, flashing can't continue..."
           exit 1
         fi
      fi
      check_file "$bl2"
      check_file "$tpl"
   fi
   if [[ $soc == "m8" ]]; then
      tpl=$tmp_dir/$uboot_comp_filename
      check_file "$tpl"
   fi
   echo -n "Initializing ddr "
   if [[ $soc == "gxl" ]] || [[ $soc == "axg" ]]; then
      run_update_assert cwr   "$bl2" $ddr_load
      run_update_assert write "$ddr" $bl2_params
      run_update_assert run          $ddr_run
      for i in {1..8}
      do
          echo -n "."
          sleep 1
      done
   fi
   if [[ $soc == "m8" ]]; then
      for i in {1..6}
      do
          echo -n "."
          sleep 1
      done
      run_update_assert cwr "$ddr"   $ddr_load
      run_update_assert run          $ddr_run
      for i in {1..4}
      do
          echo -n "."
          sleep 1
      done
   fi
   echo -e $GREEN"[OK]"$RESET

   echo -n "Running u-boot "
   if [[ $soc == "gxl" ]] || [[ $soc == "axg" ]]; then
      run_update_assert write "$bl2" $ddr_load
      run_update_assert write "$fip" $bl2_params # tell bl2 to jump to tpl, aka u-boot
      run_update_assert write "$tpl" $uboot_load
      run_update_assert run          $uboot_run
   fi
   if [[ $soc == "m8" ]]; then
      run_update_assert write "$fip" $bin_params
      run_update_assert write "$tpl" 0x00400000
      run_update_assert run          $uboot_decomp
      value=`echo "obase=16;$(($bin_params + 0x18))"|bc`
      run_update_return rreg 4 0x$value
      jump_addr=0x`echo $update_return|awk -F: '{gsub(/ /,"",$2);print $2}'`
      print_debug "Jumping to $jump_addr"
      run_update_assert run          $jump_addr
   fi
   for i in {1..8}
   do
       echo -n "."
       sleep 1
   done
   echo -e $GREEN"[OK]"$RESET

   run_update bulkcmd "low_power"

   if [[ $soc == "gxl" ]] || [[ $soc == "axg" ]]; then
      if [[ $secured == 1 ]]; then
         check_file "$tmp_dir/$dtb_meson1_filename"
      fi
      echo -n "Create partitions "
      if [[ $secured == 1 ]]; then
         run_update_assert mwrite "$tmp_dir/$dtb_meson1_filename" mem dtb normal
      else
         # We could be in the case that $dtb is signed but the board is not yet secure
         # So need to load non secure dtb here in all cases
         headstring=`head -c 4 $dtb_file`
         if [[ $headstring == "@AML" ]]; then
            check_file "$tmp_dir/$dtb_meson1_filename"
            run_update_assert mwrite "$tmp_dir/$dtb_meson1_filename" mem dtb normal
         else
            run_update_assert mwrite "$dtb_file" mem dtb normal
         fi
      fi
      if [[ $wipe == 1 ]]; then
         run_update_assert bulkcmd "disk_initial 1"
      else
         run_update_assert bulkcmd "disk_initial 0"
      fi
      echo -e $GREEN"[OK]"$RESET

      echo -n "Writing device tree "
      run_update_assert partition _aml_dtb "$dtb_file"
      echo -e $GREEN"[OK]"$RESET

      echo -n "Writing bootloader "
      run_update_assert partition bootloader "$bootloader_file"
      run_update_assert bulkcmd "env default -a"
      run_update_assert bulkcmd "saveenv"
      echo -e $GREEN"[OK]"$RESET
   else
      echo -n "Creating partitions "
      if [[ $wipe == 1 ]]; then
         run_update_assert bulkcmd "disk_initial 3"
      else
         run_update_assert bulkcmd "disk_initial 0"
      fi
      echo -e $GREEN"[OK]"$RESET

      echo -n "Writing bootloader "
      run_update_assert partition bootloader "$bootloader_file"
      echo -e $GREEN"[OK]"$RESET

      echo -n "Writing device tree "
      run_update_assert mwrite $tmp_dir/$dtb_meson_filename mem dtb normal
      echo -e $GREEN"[OK]"$RESET
   fi
fi

# Data and cache partitions wiping
# --------------------------------
if [[ $soc != "m8" ]]; then
   if [[ $wipe = 1 ]]; then
      echo -n "Wiping data partition "
      run_update bulkcmd "amlmmc erase data"
      run_update bulkcmd "nand erase.part data"
      echo -e $GREEN"[OK]"$RESET

      echo -n "Wiping cache partition "
      run_update bulkcmd "amlmmc erase cache"
      run_update bulkcmd "nand erase.part cache"
      echo -e $GREEN"[OK]"$RESET
    fi
fi

# Program all the partitions
# --------------------------
for i in $(seq 0 `expr $nb_partitions - 1`)
do
if [[ "$parts" == "all" ]] || [[ "$parts" == "${partitions_name[$i]}" ]] || [[ "$parts" == "dtb" && "${partitions_name[$i]}" == "_aml_dtb" ]]; then
   if [[ ${partitions_name[$i]} == "bootloader" ]] || [[ ${partitions_name[$i]} == "_aml_dtb" && "$parts" != "dtb" ]]; then
      continue
   fi
   check_file $tmp_dir/${partitions_file[$i]}
   if [[ $"$parts" == "dtb" ]]; then
      echo -n "Writing dtb image "
   else
      echo -n "Writing ${partitions_name[$i]} image "
   fi
   run_update_assert partition ${partitions_name[$i]} $tmp_dir/${partitions_file[$i]} ${partitions_type[$i]}
   echo -e $GREEN"[OK]"$RESET
fi
done

# Terminate burning tool
# ----------------------
echo -n "Terminate update of the board "
run_update_assert bulkcmd save_setting
echo -e $GREEN"[OK]"$RESET

# eFuse update
# ------------
if [[ $efuse_file != "" ]]; then
   check_file "$efuse_file"
   echo -n "Programming efuses "
   run_update_assert write $efuse_file 0x03000000
   run_update_assert bulkcmd "efuse amlogic_set 0x03000000"
   echo -e $GREEN"[OK]"$RESET
   run_update bulkcmd "low_power"
fi

# Cleanup
# -------
[[ -d $tmp_dir ]] && rm -rf "$tmp_dir"

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
