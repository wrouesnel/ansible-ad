## Experimental Repository of AD provisioning operatins



## Active Directory

Order of operations:

- windows-common.yml
- windows-ad-initialize.yml
- windows-ad-users.yml
- windows-ad-policy.yml

# Extras

Use `windows-pull.yml` to yank down things which are hard to edit - namely GPOs.

# Windows Server 2K22 Notes

* Enable DEP exception for MSACCESS.exe

# Spin Up with KVM Boot

```bash
./prepare-windows-iso \
    --add-boot-drivers generated/virtio-2k22/virtio/vioscsi \
    --add-boot-drivers generated/virtio-2k22/virtio/viostor \
    --add-drivers generated/virtio-2k22 \
    --add-drivers downloaded/cloudbase-init \
    --add-drivers win-common/extra \
    --add-drivers win-common/cloudbase \
    --add-drivers win-2k22-server-standard/extra \
    downloaded/SERVER_EVAL_x64FRE_en-us.iso \
    $(libvirt_default_pool)/win-2k22-Unattended-Virtio.iso \
    win-2k22-server-standard/autounattend.xml
./kvmboot --efi --windows --installer win-2k22-Unattended-Virtio.iso Win2k22-Base
./kvmboot --efi --windows lci.Win2k22-Base.root.qcow2 server-1
```

# RedHat / Fedora Notes

The included kickstart files are designed to work with setting up network secured
disk encryption. You should spin up a a RHEL/Fedora instance as a tang server
`tang.default.libvirt` first, which will then emit tang key files which should
be included in `tang.env`, and supplied with subsequent OEMDRV invocations.

## Tang Server Spin Up
```bash
./kvmboot --src-pool iso \
    --efi --video --installer \
    --oemdrv "$HOME/src/ansible-ad/kickstarts/rhel9-tang/ks.cfg" \
    rhel-9.6-x86_64-dvd.iso tang
```

The Tang server is configured to emit the key thumbprints on any available
serial port at boot. The idea being you could capture these and use them to
carry on your secure provisioning process.

## RHSM Server Spin Up

(for the enterprisey config)

```bash
./kvmboot --src-pool iso \
    --efi --video --installer \
    --oemdrv "$HOME/src/ansible-ad/kickstarts/rhel9-rhsm/ks.cfg" \
    --oemdrv "$HOME/src/ansible-ad/tang.env" \ 
    rhel-9.6-x86_64-dvd.iso rhsm
```

Together these two commands and the kickstart files create a fairly secure setup:
the root disk is default provisioned and bound to both the specific hardware
(via the TPM) and the presence of the network server.

# TODO:

What does AD need to support subid/subgid handling?

AD policy restore from zip doesn't set scope/delegation on GPOs properly (so they won't apply as expected.)

# Fedora Notes

You need this PR https://codeberg.org/jengelh/pam_mount/pulls/5 applied to pam_mount to get sensible bind mount
behavior, but it works beautifully for folder redirections.