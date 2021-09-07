.TL
Ventisrv file formats
.AU
Mechiel Lukkien
mechiel@xs4all.nl
.AI
Google Summer of Code, for the Plan 9/Inferno project
.br
August 2007
.AB
This document describes the file format used by
.I ventisrv
for its data and index file and also explains design decisions.  It should provide enough insight in the file format to help with data recovery.
.AE
.SH
Introduction
.PP
At startup,
.I ventisrv
reads the index file sequentially from start to end and places a part of the score of each stored block in memory.  The data file keeps the actual data and all relevant meta-data, enough to reconstruct an index file (though to reconstruct an index file, the entire data file has to be read).  The data file is a concatenation of blocks, each consisting of a data header followed by the data itself; compression changes this slightly.  The index file is a concatenation of index headers, each referencing a block in the data file (and in the same order).  The file formats are described first for the simple case, without support for compression;  first the data file format, followed by the index file format.  Then the file format that supports compressed blocks is described.
.SH
Format of data file
.PP
An empty (zero length) data file is simply a data file
without any blocks stored in it.  A block is stored by writing a header,
called
.I Dhdr ,
to the data file, followed by the data itself.  The header is 31 bytes
long: a 4 byte
.I magic ,
20 byte
.I score ,
1 byte
.I "data type" ,
2 byte
.I size ,
4 bytes 
.I "connection time" .
The fixed magic value is
.CW 0x2f9d81e5 .
.I Size
indicates the number of bytes following the header, thus size of the data.  Even though 2 bytes can address up to 64 kilobytes, only values up to 56 kilobytes are valid since the venti protocol does not allow larger blocks.  Note that the `zero score'—the score belonging to the zero-length data block—is never stored on disk.  It is handled internally by
.I ventisrv ,
though such a block is valid in the file format.  The
.I score
in the header is the score of the data following the header.  During operation
.I ventisrv
checks whether the score in the header matches the score it calculates from the data, to detect e.g. disk failures.  The
.I "connection time"
is the time (in seconds since UNIX epoch) at which the venti session (TCP connection) was started.  It can be used to group and relate blocks to an accidental or malicious batch of writes.
.PP
This is the definition of the
.CW Dhdr
in Limbo (with functions removed), along with the 
.I magic :
.br
.P1
 Dhdrmagic:      con big 16r2f9d81e5;

 Dhdr: adt {
        score:		Score;	# 20 bytes
        dtype:		int;	# 1 byte
        size:		int;	# 2 bytes
        conntime:	big;	# 4 bytes
 };
.P2
.SH
Format of the index file
.PP
For each block (header and data) written to the data file, an
.I Ihdr
is written to the index file.  An
.I Ihdr
is 15 bytes long: the first 8 bytes of the score called
.I halfscore ,
a 1 byte
.I "data type"
and a 6 byte
.I offset
into the data file.
.PP
Only 8 bytes from the score are stored.  Storing more is not useful: if more bytes were needed, main memory requirements would be exceed
the amount of memory that fits in a computer.  Also, the index file has to be read into memory at
.I ventisrv
startup, so it is best to keep it as small as possible.  Even 8 bytes are more than needed for almost all
.I ventisrv
installations.  Note that index headers do not contain a `magic' and do not have data following them.
.PP
Only 6 bytes are used for storing the offset into the data file.  More address space will never be needed because main memory will run out first when storing such large amounts of data.
.I Offset
is the offset in bytes into the data file to the header of the block that is referenced. Headers in the index and data file always occur in the same order.  This means the offsets in the consecutive index headers are monotonically increasing.
.PP
Below the definition of an
.CW Ihdr
in Limbo (with functions removed) is given.  The field
.I compressed
is used only for compression and can be ignored for now.
.br
.P1
 Ihdr: adt {
        halfscore:	array of byte;	# 8 bytes
        dtype:		int;		# 1 byte
        offset:		big;		# 6 bytes
        compressed:	int;
 };
.P2
.SH
File format changes to support compression
.PP
After the basic
.I ventisrv
functionality had been implemented, support for compressing blocks of data was added.  The most straight-forward implementation is to add a bit to the
.I Ihdr
to indicate whether the block is compressed; and add a similar bit to the
.I Dhdr ,
along with the size of the compressed payload (i.e. data actually on disk, which will be decompressed to the actual data).  The actual implementation is a bit different.  A new header can now occur in the data file, the
.I Fhdr
(`F' for flate, the compression algorithm used, implemented by Inferno's
.I filter-deflate(2)
module.
An
.I Fhdr
is of variable length, it contains information about one or more data blocks.  This is necessary because the compressed payload following the header contains data for multiple blocks.  The only reason for compressing multiple blocks into a single `compressed payload' is that the compression ratio will be higher: the search history for the compression algorithm will be larger, and it does not have to build up such a history for each block to compress.
.PP
The fixed-length part of an
.I Fhdr
is 7 bytes long:  a 4 byte
.I magic ,
a 1 byte
.I count
for the number of blocks stored in the compressed payload, and a 2 byte
.I size
of the compressed payload.
The fixed magic value is
.CW 0x78c66a15 .
The maximum number of compressed blocks in a single
.I Fhdr
is 256.  The size of the compressed payload is currently kept <= 56 kilobytes, though they can be up to 64 kilobytes.  The maximum size cannot be much larger because the entire compressed payload up to the needed block has to be decompressed to read that block.
.PP
The variable-length part of the header immediately follows the fixed-length part.  This variable part is made up of a header for each block stored in the compressed payload.  Each such header looks much like a
.I Dhdr ,
it is 27 bytes in size:  a 20 byte
.I score ,
1 byte
.I "data type" ,
2 byte
.I size
and 4 byte
.I "connection time" .
.I Size
is the size of the uncompressed data.  To illustrate, consider an
.I Fhdr
that represents two blocks.  On disk, it will start off with 7 bytes of fixed-size header.
The 
.I count
will be set to 2.  This header is followed immediately by 27 bytes for the first block and another 27 bytes for the second block.  After this a compressed payload follows with a
.I size
specified in the fixed-length part of the header.  Note that the entire header is stored uncompressed on file.  This allows for determining whether a score is present by only reading the header.  Compressing the 27 bytes would not be of much use anyway, since 20 bytes of out 27 are the score, which is random data to the compression algorithm.
.PP
The index header changes only slightly:  the most significant bit of the data file
.I offset
now indicates whether the header in the data file it points to is a
.I Dhdr
(when the bit is not set) or an
.I Fhdr
(when it is set).  This value is represented in the
.CW Ihdr
by the field
.I compressed .
Headers in the index file are still in the same order of appearance as the blocks in the data file.  Note that each stored score is given a header in the index file.  This includes possible multiple scores in a single
.I Fhdr
in the data file:  they each get an
.I Ihdr ,
with the data file offset pointing to the same location in the data file.  A program performing a lookup has to find the right score in the
.I Fhdr
itself.
.PP
.I Ventisrv
assumes data will compress to at most 90% of the original size.  When the current compression buffer has no room for another block the
.I Fhdr
is written to disk.  If
.I ventisrv
tries adding a compressed block—which was supposed to fit based on the 90%-size assumption—but the maximum compressed buffer size is exceeded, the blocks are written to the data file without compression, as
.I Dhdr
blocks.
In other words,
.I Fhdr
and
.I Dhdr
blocks can be mixed freely in the data file.
.SH
Conclusions
.PP
Support for compression makes the file format more complex, but not significantly so.  Improvements could be made in the area of compression.  For example, another compression algorithm could be used, one that depends less on building up compression history, or has some predefined histories to choose from.  Also, since compression is relatively slow, a faster compression algorithm would be welcome.  Early detection of whether data is compressible can alleviate the problem of slow compression somewhat.  The header format would not necessarily have to change to accommodate for this.
.PP
The index and data files contain enough information to cross-check the validity of the data blocks.
.I Ventisrv
performs such checks on the most recently written blocks in these files at startup.  The data file is always written before the index header is written, though not flushed explicitly, so the index file may be flushed in the background by a file system scheduler.  In any case, missing headers in the index file are automatically added by
.I ventisrv
at startup, missing data file blocks are a fatal error and need to be resolved manually (by removing the index headers).  The only remaining question is what to do with permanently damaged and non-recoverable (e.g. from backup) data blocks.  Ideally, it should be possible to mark a data block as invalid, at least in the data file.  There is currently no way to mark a block as such.
