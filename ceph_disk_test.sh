#!/bin/bash

# This script calls FIO to provide a full battery of performance tests
# to gauge the performance of a disk as both a Ceph OSD and journal
# it also plots graphs for all performance characteristics of the disk

#
# Let's tell the user about usage if they don't supply enough arguments
#

if [ -z "$6" ]; then
  echo 'Usage:  sudo ceph_disk_test.sh <device name> <data set size> <block size> <test duration in seconds> <type: osd or journal> <test-name>'
  echo
  echo "Example:"
  echo '        sudo ceph_disk_test.sh /dev/sdn 10240m 4m 300 journal intel-dc3700'
  echo
  exit 1
fi

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
    echo $(getDate) "Concurrent Object storage performance testing must be run as root or via sudo - aborting." | tee -a logs/$logdate-cluster-info.log
    exit 1
fi

GNUPLOT=$(which gnuplot)
if [ ! -x $GNUPLOT ]; then
    echo You need gnuplot installed to generate graphs
    exit 1
fi

FIO=$(which fio)
if [ ! -x $FIO ]; then
    echo You need fio installed to run IO tests
    exit 1
fi

function getTmpMount () {
    # Generates a temporary mount point
    tmpmount=$(mktemp -d)
    echo $tmpmount
}

function getDate() {
  # Get the date and echo it
  echo $(date +%F\ %H:%M:%S) $(hostname -s)
}

echo $(getDate) 'Creating Mount Points'

# Set the global variables from user input and create mount points
tmpmountpoint=$(getTmpMount)
drive=$1
size=$2
blocksize=$3
duration=$4
type=$5
name=$6
tmplogs=$(getTmpMount)
ourpwd=$(pwd)
logdate=$(date +%y%m%d-%H%M)
durationmultiplier=8
totalduration=$(($duration * $durationmultiplier))

function createTest () {
    # Creates the fio test file using a here document
    testmountpoint=$1
    testsize=$2
    testblocksize=$3
    testduration=$4
    testtype=$5
    
    if [ "$testtype" == "osd" ]; then
    
        cat <<EOF > ${tmplogs}/$logdate-osd-$size-$name.fio
[global]
ioengine=libaio
invalidate=1
ramp_time=5
iodepth=32
runtime=${testduration}
time_based
direct=0
bs=${testblocksize}
size=${testsize}
filename=${testmountpoint}/test.file
 
[seq-write]
stonewall
rw=write
write_bw_log=${tmplogs}/$logdate-seq-write-osd-$size-$name
write_lat_log=${tmplogs}/$logdate-seq-write-osd-$size-$name
write_iops_log=${tmplogs}/$logdate-seq-write-osd-$size-$name
write_iolog=${tmplogs}/$logdate-seq-write-osd-$size-$name
 
[rand-write]
stonewall
rw=randwrite
write_bw_log=${tmplogs}/$logdate-rand-write-osd-$size-$name
write_lat_log=${tmplogs}/$logdate-rand-write-osd-$size-$name
write_iops_log=${tmplogs}/$logdate-rand-write-osd-$size-$name
write_iolog=${tmplogs}/$logdate-rand-write-osd-$size-$name
 
[seq-read]
stonewall
rw=read
write_bw_log=${tmplogs}/$logdate-seq-read-osd-$size-$name
write_lat_log=${tmplogs}/$logdate-seq-read-osd-$size-$name
write_iops_log=${tmplogs}/$logdate-seq-read-osd-$size-$name
write_iolog=${tmplogs}/$logdate-seq-read-osd-$size-$name
 
[rand-read]
stonewall
rw=randread
write_bw_log=${tmplogs}/$logdate-rand-read-osd-$size-$name
write_lat_log=${tmplogs}/$logdate-rand-read-osd-$size-$name
write_iops_log=${tmplogs}/$logdate-rand-read-osd-$size-$name
write_iolog=${tmplogs}/$logdate-rand-read-osd-$size-$name
EOF
    elif [ "$testtype" == "journal" ]; then
        cat <<EOF > ${tmplogs}/$logdate-journal-$size-$name.fio
[global]
ioengine=libaio
invalidate=1
ramp_time=5
iodepth=1
runtime=${testduration}
time_based
direct=1
sync=1
bs=${testblocksize}
size=${testsize}
filename=${testmountpoint}/test.file
 
[seq-write]
stonewall
rw=write
write_bw_log=${tmplogs}/$logdate-seq-write-journal-$size-$name
write_lat_log=${tmplogs}/$logdate-seq-write-journal-$size-$name
write_iops_log=${tmplogs}/$logdate-seq-write-journal-$size-$name
write_iolog=${tmplogs}/$logdate-seq-write-journal-$size-$name
 
[rand-write]
stonewall
rw=randwrite
write_bw_log=${tmplogs}/$logdate-rand-write-journal-$size-$name
write_lat_log=${tmplogs}/$logdate-rand-write-journal-$size-$name
write_iops_log=${tmplogs}/$logdate-rand-write-journal-$size-$name
write_iolog=${tmplogs}/$logdate-rand-write-journal-$size-$name
 
[seq-read]
stonewall
rw=read
write_bw_log=${tmplogs}/$logdate-seq-read-journal-$size-$name
write_lat_log=${tmplogs}/$logdate-seq-read-journal-$size-$name
write_iops_log=${tmplogs}/$logdate-seq-read-journal-$size-$name
write_iolog=${tmplogs}/$logdate-seq-read-journal-$size-$name
 
[rand-read]
stonewall
rw=randread
write_bw_log=${tmplogs}/$logdate-rand-read-journal-$size-$name
write_lat_log=${tmplogs}/$logdate-rand-read-journal-$size-$name
write_iops_log=${tmplogs}/$logdate-rand-read-journal-$size-$name
write_iolog=${tmplogs}/$logdate-rand-read-journal-$size-$name
EOF
    fi
}

plot () {
    #
    # plot <sub title> <file name tag> <y axis label> <y axis scale>
    #
    
    if [ -z "$TITLE" ]
    then    
        PLOT_TITLE=" set title \"$1\" font $DEFAULT_TITLE_FONT"
    else
        PLOT_TITLE=" set title \"$TITLE\\n\\n{/*0.6 "$1"}\" font $DEFAULT_TITLE_FONT"
    fi
    FILETYPE="$2"
    YAXIS="set ylabel \"$3\" font $DEFAULT_AXIS_LABEL_FONT"
    SCALE=$4

    echo "Title: $PLOT_TITLE"
    echo "File type: $FILETYPE"
    echo "yaxis: $YAXIS"

    i=0
    
    for x in *_"$FILETYPE".*.log
    do
        i=$((i+1))
        PT=$(echo $x | sed s/_"$FILETYPE".*.log//g)
        if [ ! -z "$PLOT_LINE" ]
        then
            PLOT_LINE=$PLOT_LINE", "
        fi

        DEPTH=$(echo $PT)
        PLOT_LINE=$PLOT_LINE"'$x' using (\$1/1000):(\$2/$SCALE) title \" $DEPTH\" with lines ls $i" 
        
    done

    OUTPUT="set output \"$TITLE-$FILETYPE.svg\" "

    echo " $PLOT_TITLE ; $YAXIS ; $DEFAULT_OPTS ; show style lines ; $OUTPUT ; plot "  $PLOT_LINE  | $GNUPLOT -
    unset PLOT_LINE
}

function fioGeneratePlots () {

    TITLE="$1"

    # set resolution
    if [ ! -z "$2" ] && [ ! -z "$3" ]
    then
        XRES="$2"
        YRES="$3"
    else
        XRES=1920
        YRES=1080
    fi
    
    if [ -z "$SAMPLE_DURATION" ]
    then
        SAMPLE_DURATION="*"
    fi
    
    DEFAULT_GRID_LINE_TYPE=3
    DEFAULT_LINE_WIDTH=2
    DEFAULT_LINE_COLORS="
    set object 1 rectangle from screen 0,0 to screen 1,1 fillcolor rgb\"#ffffff\" behind 
    set style line 1 lc rgb \"#E41A1C\" lw $DEFAULT_LINE_WIDTH lt 1;
    set style line 2 lc rgb \"#377EB8\" lw $DEFAULT_LINE_WIDTH lt 1;
    set style line 3 lc rgb \"#4DAF4A\" lw $DEFAULT_LINE_WIDTH lt 1;
    set style line 4 lc rgb \"#984EA3\" lw $DEFAULT_LINE_WIDTH lt 1;
    set style line 5 lc rgb \"#FF7F00\" lw $DEFAULT_LINE_WIDTH lt 1;
    set style line 6 lc rgb \"#DADA33\" lw $DEFAULT_LINE_WIDTH lt 1;
    set style line 7 lc rgb \"#A65628\" lw $DEFAULT_LINE_WIDTH lt 1;
    set style line 20 lc rgb \"#000000\" lt $DEFAULT_GRID_LINE_TYPE lw $DEFAULT_LINE_WIDTH;
    "
    
    DEFAULT_TERMINAL="set terminal svg enhanced dashed size $XRES,$YRES dynamic"
    DEFAULT_TITLE_FONT="\"Helvetica,28\""
    DEFAULT_AXIS_FONT="\"Helvetica,14\""
    DEFAULT_AXIS_LABEL_FONT="\"Helvetica,16\""
    DEFAULT_XLABEL="set xlabel \"Time (sec)\" font $DEFAULT_AXIS_LABEL_FONT"
    DEFAULT_XTIC="set xtics font $DEFAULT_AXIS_FONT"
    DEFAULT_YTIC="set ytics font $DEFAULT_AXIS_FONT"
    DEFAULT_MXTIC="set mxtics 0"
    DEFAULT_MYTIC="set mytics 2"
    DEFAULT_XRANGE="set xrange [0:$SAMPLE_DURATION]"
    DEFAULT_YRANGE="set yrange [0:*]"
    DEFAULT_GRID="set grid ls 20"
    DEFAULT_KEY="set key outside bottom center ; set key box enhanced spacing 2.0 samplen 3 horizontal width 4 height 1.2 "
    DEFAULT_SOURCE='set label 30 "Data source: http://www.example.com" font "Helvetica,14" tc rgb "#00000f" at screen 0.976,0.175 right'
    DEFAULT_OPTS="$DEFAULT_LINE_COLORS ; $DEFAULT_GRID_LINE ; $DEFAULT_GRID ; $DEFAULT_GRID_MINOR ; $DEFAULT_XLABEL ; $DEFAULT_XRANGE ; $DEFAULT_YRANGE ; $DEFAULT_XTIC ;  $DEFAULT_YTIC ; $DEFAULT_MXTIC ;     $DEFAULT_MYTIC ; $DEFAULT_KEY ; $DEFAULT_TERMINAL ; $DEFAULT_SOURCE"
    
    plot "I/O Latency" lat "Time (msec)" 1000
    plot "I/O Operations Per Second" iops "IOPS" 1
    plot "I/O Submission Latency" slat "Time (μsec)" 1
    plot "I/O Completion Latency" clat "Time (msec)" 1000
    plot "I/O Bandwidth" bw "Throughput (KB/s)" 1
}

function generatePlots () {
        cd $tmplogs
    # Generate graphs from test data
    if [ "$testtype" == "osd" ]; then
        fioGeneratePlots $logdate-osd-$name
    elif [ "$testtype" == "journal" ]; then
        fioGeneratePlots $logdate-journal-$name
    fi
    cd $ourpwd
}

function runTest () {
    # Run the fio test
    if [ "$testtype" == "osd" ]; then
        fio ${tmplogs}/$logdate-osd-$size-$name.fio | tee ${tmplogs}/$logdate-osd-$size-$name.log
    elif [ "$testtype" == "journal" ]; then
        fio ${tmplogs}/$logdate-journal-$size-$name.fio | tee ${tmplogs}/$logdate-osd-$size-$name.log
    fi
}

function wipeDrive() {
    # Wipe the drive and partition table
    umount $drive >/dev/null 2>&1
    wipefs -a $drive
    cat <<EOF | sudo gdisk $drive
o
Y
n
1



w
Y
EOF
}

function filesystemCreate () {
    # Create XFS filesystem
    mkfs.xfs -f -i size=2048 -n size=8k ${drive}1
}

function mountDrive () {
    # Mount drive with ceph parameters
    mount -o noatime,nodiratime,attr2,logbufs=8,logbsize=256k,inode64,allocsize=4m ${drive}1 $tmpmountpoint
}

function umountDrive () {
    # Unmount drive
    umount $tmpmountpoint
    # Clean up the mount point
        rm -R -f ${tmpmountpoint}
}

function makeArchive () {
    cd ${tmplogs}
    tar -cf - * | xz -9 -c - > ${ourpwd}/${logdate}-${testtype}-${size}-${name}.tar.xz
    # Clean out the logs directory
    cd ${ourpwd}
    rm -R -f ${tmplogs}
}

function dropCaches () {
    echo 3 > /proc/sys/vm/drop_caches
    sync
}
        
function main () {
    # The main function of the script
    echo $(getDate) "Creating Test Files at ${tmplog}"
    createTest $tmpmountpoint $size $blocksize $duration $type
    echo $(getDate) "Formatting Drive $drive"
    wipeDrive
    filesystemCreate
    echo $(getDate) "Mounting Drive $drive at $tmpmountpoint"
    mountDrive
    echo $(getDate) "Dropping OS Caches / Unused inodes, dentries"
    dropCaches
    echo $(getDate) "Running Tests for $totalduration seconds..."
    runTest
    echo $(getDate) "Unmounting Drive $drive from $tmpmountpoint"
    umountDrive
    echo $(getDate) 'Graphing Results'
    generatePlots
    echo $(getDate) 'Compressing Results'
    makeArchive
    echo $(getDate) "Test results at ${ourpwd}/${logdate}-${testtype}-${size}-${name}.tar.xz"
}

main
