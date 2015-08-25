# ceph-disk-test

ceph-disk-test is a testing utility that uses fio, gnuplotter and a modified
version of the fio_generate_plots script, along with some best practices.

The tool will test a physical disk for performance as either a ceph OSD or
journal drive and plot it on a graph.
