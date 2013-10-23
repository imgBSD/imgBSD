imgbsd
======

All the files and scripts in this repository produce one simple outcome, a
customized FreeBSD Desktop OS in an image.

Building the image is split into two main sections, the base and the top.

For more information see the following two websites:
www.imgbsd.org
wiki.imgbsd.org

===> Base
The base is mainly just the compiled FreeBSD source and kernel, built with the
predefined configurations held in base.conf.default (chosen specifically for
imgBSD).
The base was split from the rest of the process as it can take some time to
compile and the configuration will rarely change over time. This also allows
different projects with different goals to share the same base, or core, and
the specialization to be made in the top.
The base archive will also contain the build logs of the base compilation
process.
At the end of the base build process you should have a tar.xz archive ready to
start building tops.

===> Top
The top is comprised of a specified base archive, any installed ports (provided
as txz packages), custom scripts, modifications to the base and also port
configuration changes.
The top (or topping) is where is where a completely different and customized
image can be produced within minutes, which size could be anywhere from 100MB to
several gigabytes.
At the end of the process you should end up with an img binary ending in img.xz.


Building
========
1. Checkout sources
First you must checkout the imgBSD sources:
cd ~/
git clone https://github.com/imgBSD/imgBSD



2. Base
You have two choices for obtaining the required base archive, either build it
yourself or download a pre-built release version. Compiling yourself will allow
for customization (adding/removing FreeBSD features or a custom kernel
configuration). The drawback is that it can take some time to compile (30min on
an intel i5 with 16GB ram and on a ramdisk), can be tricky to get the correct
compile options (due to dependencies) and finally means you will have to
checkout the FreeBSD sources with SVN.
However, the pre-built binary is around a 60MB file to download and will
generally be compatible with the scripts for building the top.

===> Compiling yourself
Depending on your location you can get the source with one of the following
commands.
svn checkout https://svn0.eu.FreeBSD.org/base/release/9.1.0 FreeBSD_src-9.1
svn checkout https://svn0.us-west.FreeBSD.org/release/9.1.0 FreeBSD_src-9.1

cd ~/imgBSD
cp imgBSD/conf/base.conf.default imgBSD/conf/base.conf

Now edit imgBSD/conf/base.conf file to setup your environment and compile
options. The imgBSD/conf/kernel_* is the default kernel conf used in the build
process.

./create-base.sh -c imgBSD/conf/base.conf

Alternative:
===> Downloading the base
The latest base can be downloaded from here:
http://www.imgbsd.org/latest_base.xz

You might want to check the following page to make sure you end up with a base
that matches the top you wish to build.
http://www.imgbsd.org/releases.htm



3. Top
cd ~/imgBSD
cp imgBSD/conf/top.conf.default imgBSD/conf/top.conf
Edit imgBSD/conf/top.conf file to setup your environment.

===> Compile the ports
You will need to build the collection of packages matching the list in
imgBSD/conf/ports (this list does not contain dependencies, only ports to be
required to be installed). If using poudriere (which is recommended) there is a
make configuration file which has customized dependency options helping to
reduce the size of the image.
Alternatively you can download the all the packages used to create the the
current image from the following page: http://www.imgbsd.org/releases.htm

===> Creating an img binary

cd ~/imgBSD
./create-top.sh -c imgBSD/conf/top.conf

Your image will be created after 10-20 minutes (with SSD's/ramdisks making the
process significantly faster) and will be placed in the direcotry that you set
"IMG_STORE_DIR" to in the top conf file.

