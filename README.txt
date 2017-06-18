Hi,

This is the flash-tool for Amlogic platforms.
This flash-tool script rely on update linux tool that need firstly to be installed.
Please read the file tools/_install_/README before to proceed here.

After than you can call flash-tool.sh from anywhere, it will give you quick help :

Usage      : ./flash-tool.sh --target-out=<aosp output directory> --parts=<all|none|logo|recovery|boot|system> [--skip-uboot] [--wipe] [--reset=<y|n>] [--linux] [--soc=<gxl|axg|m8>] [*-file=/path/to/file/location] [--password=/path/to/password.bin]
Version    : 3.1
Parameters : --target-out   => Specify location path where are all the images to burn or path to aml_upgrade_package.img
             --parts        => Specify which partitions to burn
             --skip-uboot   => Will not burn uboot
             --wipe         => Destroy all partitions
             --reset        => Force reset mode at the end of the burning
             --soc          => Force soc type (gxl=S905/S912,axg=A113,m8=S805...)
             --linux        => Specify the image to flash is linux not android
             --efuse-file   => Force efuse OTP burn, use this option carefully
             --uboot-file   => Overload default uboot.bin file to be used
             --dtb-file     => Overload default dtb.img file to be used
             --boot-file    => Overload default boot.img file to be used
             --recover-file => Overload default recovery.img file to be used
             --password     => Unlock usb mode using password file provided
             --destroy      => Erase the bootloader and reset the board

Before to enter in the details here, let's explain how the connection work with the Amlogic board.

First you neeed to connect the board to your linux pc with a usb cable.
It can be done using a cable (USB Type A to USB Type A) or (USB Type A to USB Micro-B 5 pin).
It depends how the board has been designed actually.

The port to be used on the board is also dependant of the hardware. But you have to know that one particular USB 
port will be configured in slave mode at boot stage in two cases :

1/ No valid boot image can be found to boot on it, the Soc goes directly in usb boot mode
2/ USB boot mode forced in current u-boot flashed with the 'update' command.

When the Soc is in USB mode, if you have installed properly the update binary tool, your linux machine
should detect a new usb device called /dev/worldcup

By calling dmesg, you should see something like :

[19519.971862] usb 3-3.2: USB disconnect, device number 28
[40055.121229] usb 3-3.2: new high-speed USB device number 29 using xhci_hcd
[40055.212495] usb 3-3.2: New USB device found, idVendor=1b8e, idProduct=c003
[40055.212498] usb 3-3.2: New USB device strings: Mfr=0, Product=0, SerialNumber=0

It's important to see this before to proceed on the next step, otherwise it will not work.

If all is here, it means you are now ready to flash the board or/and to control it from your PC machine

If you have already built android tree or linux tree, you can directly flash you new images by doing this : 

$ flash-tool.sh --target-out=/path/to/aml_upgrade_package.img --parts=all --wipe

Add the --linux option if you are flashing a linux env :

$ flash-tool.sh --target-out=/path/to/aml_upgrade_package.img --parts=all --wipe --linux

Also sometimes, it could be nice to update only some partitions but not all of them.
It can be done using the --parts parameter. For example here, we just reflash the system android partition with :

$ flash-tool.sh --target-out=/path/to/aml_upgrade_package.img --parts=system

Now when we want flash delocalized files that are not in --target-out, we can force file paths using *-file options 
like --uboot-file,--dtb-file,--boot-file,--recovery-file....
It could be the case when you just sign some images that are placed in a different directory but want to keep same non signed
partitions also like system.img, logo.img, etc.
In this case you can do this :

$ flash-tool.sh --target-out=/path/to/aml_upgrade_package.img \
                --parts=all \
                --wipe \
                --uboot-file=/path/to/output/u-boot.bin.signed \
                --dtb-file=/path/to/output/dtb.img.signed \
                --boot-file=/path/to/output/boot.img.signed \
                --recover-file=/path/to/output/recovery.img.signed

You can also burn the efuse in the same way with :

$ flash-tool.sh --target-out=/path/to/aml_upgrade_package.img \
                --parts=all \
                --wipe \
                --uboot-file=/path/to/output/u-boot.bin.signed \
                --dtb-file=/path/to/output/dtb.img.signed \
                --boot-file=/path/to/output/boot.img.signed \
                --recover-file=/path/to/output/recovery.img.signed \
                --efuse-file=/path/to/output/pattern.efuse.uboot

Enjoy!

Marco (c) Amlogic
