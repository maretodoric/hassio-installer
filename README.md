# Home Assistant OS Installer

Hello everyone.

I would like to present to you Home Assistant OS Installer for Generic x64-64 devices.

## Background
Recently I've been planning to move from Raspberry Pi 3B+ to dedicated PC running Home Assistant OS, however official documentation for installing Home Assistant OS on Generic x64-64 device states that you need to write OS image to boot media and suggesting to either hookup the drive using USB to SATA adapter, then flash the image or by booting a live linux, downloading the OS image and writing it to drive. They also did mention that they do not yet have a dedicated installer.
In both cases you need to do some prep work by downloading the image, waiting for download to finish, then waiting for the time being while image is flashed. You also need to handle any prereqs (if any/needed).

Honestly, i was too lazy to do any of two options and decided to spend more time (than i would need to if i chose either option) and actually create a dedicated Home Assistant OS Installer.

This lightweight ISO (~157MB) can be quickly flashed to your USB drive comparing to large Ubuntu live and will automatically prompt you to select which Home Assistant OS you want to install.

It will also detect if drive you're trying to install it to contains some data and will prompt to format it (SSDs can be Secure Erased if needed)

Installation will not require any additional space on USB where you will boot the installer from as the installer will stream Home Assistant OS image directly to your drive, after which you can continue to boot your instance as you would normally do. This means that you don't need to worry about additional 6GB space that Hass OS has after it's uncompressed, and you can flash this on a small 1-2GB USB drive.

## Usage
- Write ISO to flash drive using rufus, dd on linux or similar tool
- Boot from USB like you would normally boot any OS
- Follow intuitive on-screen menu to install the OS, some screenshots can be found in 'screenshots' folder in this repo

## Features
- Auto IP asssignment via DHCP
- Selection of OS version to install, it will prompt for last 10 stable (non RC) versions
- Selection of drive where to install with displaying of drive space and model for easy recognition
- If drive contains data, it will prompt to perform quick erase (just erases partition tables) or full (writes zeroes to drive)
- If SSD is selected for full erase, it will try to perform Secure Erase rather than writing zeroes, since it's not recommended to write zeroes to SSD

## Known limitations
- Unable to manually configure IP address, only via DHCP at the moment.
- Wi-Fi connection not yet supported, unfortunately i don't have hardware to test it on to make it work.
- NVMe Sanitize (Something like SSD Secure Erase) not yet implemented and falls back to writing zeroes.
