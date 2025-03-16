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

# TODO:

What does AD need to support subid/subgid handling?

AD policy restore from zip doesn't set scope/delegation on GPOs properly (so they won't apply as expected.)