# ventivac

this is the result of the "ventivac" google summer of code project for
the "plan 9 from bell labs/inferno" software project, as described at:

	http://code.google.com/soc/2007/p9/appinfo.html?csaid=D99356B8E1636AC0


vacfs, vacget and vacput (and the vac library of course), are now in
the inferno-os subversion distribution.  this hg repository contains
the latest versions of the code for testing.

ventisrv and vcache are not in inferno-os svn, only in this repository.
this repository now also includes a copy of the venti library and manual
page from inferno-os.

now how to install this code:

1. you need a mkconfig in this directory.  a bind/symlink to the inferno
   install mkconfig will do.

2. you must create a /dis/venti to hold a few venti programs.

3. now just running "mk install" will copy module/vac.m into your /module,
   and compile all limbo files and install them as well.


the programs that are installed by the mkfiles all have manual pages.
except for appl/lib/venti.b and man/2/venti (which are originally from
inferno-os svn but have been modified slightly), the files in this
repository are under the standard MIT-licence as recommended for all plan
9 google summer of code projects.

progress reports have been made during the project, and will be kept up
to date with the latest changes at:

	http://gsoc.cat-v.org/people/mjl/blog/

the mercurial repository will be used for future changes, it can be
found at:

	http://gsoc.cat-v.org/hg/ventivac/

additionally, i will keep a page about ventivac updated on my own
website at:

	http://www.xs4all.nl/~mechiel/inferno/ventivac/

if these were both to fail, you should be able to reach me at either
mechiel@xs4all.nl, or mechiel@ueber.net.


special thanks go to charles forsyth from vitanuova for mentoring this
project!

special thanks also go to uriel mangado for overseeing the entire
plan 9 from bell labs/inferno google summer of code presence.


other notes:

- appl/cmd/testrabin.b reads a file and splits it using appl/lib/rabin.b.
  the parameters for the rabin algorithm can be set from the command-line,
  making it usable for testing.
- appl/cmd/rabinparams.b walks a directory and splits all files with rabin
  fingerprinting.  when done, it prints a histogram of each occuring
  block size, how many blocks were found and what the mean block size was.
  it can also print all boundaries to stderr.
- doc/ventisrv-fileformat.[pm]s, troff source and rendered postscript
  of document describing the file format used by ventisrv for its data
  and index files.
- the main idea of ventisrv, storing the scores partially, comes from my
  master's thesis in which a similar program (but with less functionality)
  is designed.
