#!/bin/sh

#
# Copyright (c) 2014 EMC Corp.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

# No problems seen.

[ `id -u ` -ne 0 ] && echo "Must be root!" && exit 1

. ../default.cfg

md1=$mdstart
md2=$((mdstart + 1))
md3=$((mdstart + 2))

s=0
size=1g
[ $((`sysctl -n hw.usermem` / 1024 / 1024 / 1024)) -le 4 ] &&
    size=512m

for u in $md1 $md2 $md3; do
	mdconfig -l | grep -q md$u && mdconfig -d -u $u
	mdconfig -a -t swap -s $size -u $u
done

gmirror load > /dev/null 2>&1 && unload=1
old=`sysctl -n kern.geom.mirror.debug`
sysctl kern.geom.mirror.debug=-1 | grep -q -- -1 ||
    sysctl kern.geom.mirror.debug=$old > /dev/null
gmirror label -v -b split -s 2048 data /dev/md$md1 /dev/md$md2 \
    /dev/md$md3 > /dev/null || exit 1
[ "`sysctl -in kern.geom.mirror.launch_mirror_before_timeout`" = "0" ] &&
    sleep $((`sysctl -n kern.geom.mirror.timeout` + 1))
[ -c /dev/mirror/data ] || exit 1
newfs $newfs_flags /dev/mirror/data > /dev/null
mount /dev/mirror/data $mntpoint
chmod 777 $mntpoint

export runRUNTIME=10m
export RUNDIR=$mntpoint/stressX

su $testuser -c 'cd ..; ./run.sh marcus.cfg'
for i in `jot 6`; do
	mount | grep -q "on $mntpoint " || break
	umount $mntpoint && break || sleep 10
	[ $i -eq 6 ] &&
	    { echo FATAL; fstat -mf $mntpoint; exit 1; }
done
checkfs /dev/mirror/data || s=1
gmirror stop data || s=2
gmirror destroy data 2>/dev/null
[ $unload ] && gmirror unload

for u in $md3 $md2 $md1; do
	mdconfig -d -u $u || s=3
done
exit $s
