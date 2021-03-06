ARCH="x86_64"
RHCOSVERSION="4.4.3"
HOME_DIR="/home/snelson/Repositories/ConsultingGitLab/OCP4"
BASE_URL="http://localhost"
BOOTIMG="rhcos-${RHCOSVERSION}-${ARCH}-installer.${ARCH}.iso"
DISKIMG="rhcos-${RHCOSVERSION}-${ARCH}-metal.${ARCH}.raw.gz"

CLUSTER_NAME="ocp4"
DOMAIN_NAME="example.com"
GATEWAY="10.0.0.1"
NETMASK="255.255.255.0"
NET_INTERFACE="bond0.120"

export VOLID=$(isoinfo -d -i ${HOME_DIR}/${BOOTIMG} | awk '/Volume id/ { print $3 }')
TEMPDIR=$(mktemp -d)

cd ${TEMPDIR}
# Extract the ISO content using guestfish (to avoid sudo mount)
guestfish -a ${HOME_DIR}/${BOOTIMG} -m /dev/sda tar-out / - | tar xvf -

# Helper function to modify the config files
modify_cfg(){
  KCMD_DEV="coreos.inst.install_dev=${DISK}"
  KCMD_IMAGE_URL="coreos.inst.image_url=${BASE_URL}/${DISKIMG}"
  KCMD_IGNITION_URL="coreos.inst.ignition_url=${BASE_URL}/${NODE}.ign"
  KCMD_IP="ip=${IP}::${GATEWAY}:${NETMASK}:${FQDN}:${NET_INTERFACE}:none nameserver=${DNS}"
  KCMD_ADDL="bond=bond0:eno5,eno6:mode=4,miimon=100 vlan=bond0.120:bond0 ipv6.disable=1"
  KCMD="${KCMD_DEV} ${KCMD_IMAGE_URL} ${KCMD_IGNITION_URL} ${KCMD_IP} ${KCMD_ADDL}"

  for file in "EFI/redhat/grub.cfg" "isolinux/isolinux.cfg"; do
    # Append the proper image and ignition urls
    sed -e '/coreos.inst=yes/s|$| '"${KCMD}"' |' ${file} > $(pwd)/${NODE}_${file##*/}
    # Boot directly in the installation
    sed -i -e 's/default vesamenu.c32/default linux/g' -e 's/timeout 600/timeout 10/g' $(pwd)/${NODE}_${file##*/}
  done
}

# BOOTSTRAP
TYPE="bootstrap"
NODE="bootstrap"
IP="10.0.0.9"
FQDN="bootstrap.${CLUSTER_NAME}.${DOMAIN_NAME}"
DISK="sda"
modify_cfg

# MASTERS
TYPE="master"
# MASTER-0
NODE="master-0"
IP="10.0.0.21"
FQDN="${NODE}.${CLUSTER_NAME}.${DOMAIN_NAME}"
DISK="sda"
modify_cfg

# MASTER-1
NODE="master-1"
IP="10.0.0.22"
FQDN="${NODE}.${CLUSTER_NAME}.${DOMAIN_NAME}"
DISK="sda"
modify_cfg

# MASTER-2
NODE="master-2"
IP="10.0.0.23"
FQDN="${NODE}.${CLUSTER_NAME}.${DOMAIN_NAME}"
DISK="sda"
modify_cfg

# WORKERS
TYPE="worker"
# WORKER-0
NODE="worker-0"
IP="10.0.0.31"
FQDN="${NODE}.${CLUSTER_NAME}.${DOMAIN_NAME}"
DISK="sda"
modify_cfg

# Generate the images, one per node as the IP configuration is different...
# https://github.com/coreos/coreos-assembler/blob/master/src/cmd-buildextend-installer#L97-L103
for node in bootstrap master-0 master-1 master-2 worker-0; do
  # Overwrite the grub.cfg and isolinux.cfg files for each node type
  for file in "EFI/redhat/grub.cfg" "isolinux/isolinux.cfg"; do
    cp $(pwd)/${node}_${file##*/} ${file}
  done
  # As regular user!
  genisoimage -verbose -rock -J -joliet-long -volset ${VOLID} \
    -eltorito-boot isolinux/isolinux.bin -eltorito-catalog isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -efi-boot images/efiboot.img -no-emul-boot \
    -o ${HOME_DIR}/${node}.iso .
done

# Optionally, clean up
# cd
# rm -Rf ${TEMPDIR}