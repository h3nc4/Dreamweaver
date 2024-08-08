# Optimize windows vw qemu virt manager

https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/

## xml

### remove the following lines from the xml file of the vm

    <timer name="rtc" tickpolicy="catchup"/>
    <timer name="pit" tickpolicy="delay"/>

### change this guy to yes

    <timer name="hpet" present="yes"/>

### replace hyperv with this

    <hyperv mode="custom">
        <relaxed state="on"/>
        <vapic state="on"/>
        <spinlocks state="on" retries="8191"/>
        <vpindex state="on"/>
        <runtime state="on"/>
        <synic state="on"/>
        <stimer state="on">
        <direct state="on"/>
        </stimer>
        <reset state="on"/>
        <vendor_id state="on" value="KVM Hv"/>
        <frequencies state="on"/>
        <reenlightenment state="on"/>
        <tlbflush state="on"/>
        <ipi state="on"/>
        <evmcs state="on"/>
    </hyperv>

if on amd, remove <evmcs state="on"/>

## cpu

change the cpu topology to something that makes sense

## disk

change the disk to virtio

set the cache to none

## network

change the network to virtio

## drivers

add hardware -> device type -> cdrom -> select the virtio-win iso

## tablet

remove the tablet

## TPM

change version to 2.0

## installation

on the windows installation screen, press load driver and load the virtio drivers for the disk virtio

the network virtio drivers wont show at first, go to browse and select the folder NetKVM\w10\amd64, then the drivers will show up. select the driver and install it

## after installation

install the virtio guest tools from the virtio-win iso
