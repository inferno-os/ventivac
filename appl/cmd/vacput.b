implement Vacput;

include "sys.m";
	sys: Sys;
include "draw.m";
include "daytime.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
include "string.m";
include "venti.m";
include "vac.m";
include "rabin.m";

daytime: Daytime;
str: String;
venti: Venti;
vac: Vac;
rabin: Rabin;

print, sprint, fprint, fildes: import sys;
Score, Session: import venti;
Entry, Entrysize, Root, Roottype, Dirtype, Datatype: import venti;
Direntry, File, Sink, MSink, Vacdir: import vac;
Rcfg, Rfile: import rabin;

Vacput: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
Dflag, vflag, qflag, rflag: int;
blocksize := Venti->Dsize;
session: ref Session;
name := "vac";
basescore: ref Score;
rcfg: ref Rcfg;
blockmin, blockmax: int;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	daytime = load Daytime Daytime->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	venti = load Venti Venti->PATH;
	vac = load Vac Vac->PATH;
	rabin = load Rabin Rabin->PATH;

	venti->init();
	vac->init();
	rabin->init(bufio);

	prime := Vac->Rabinprime;
	mod := Vac->Rabinmod;
	width := Vac->Rabinwidth;
	blockmin = Vac->Rabinblockmin;
	blockmax = Vac->Rabinblockmax;

	arg->init(args);
	arg->setusage(sprint("%s [-Dqrv] [-a addr] [-b blocksize] [-d vacfile] [-n name] path ...", arg->progname()));
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'b' =>	blocksize = int arg->earg();
		'n' =>	name = arg->earg();
		'd' =>
			err: string;
			(nil, basescore, err) = vac->readscore(arg->earg());
			if(err != nil)
				error("reading score: "+err);
		'D' =>	Dflag++;
			rabin->debug++;
			vflag++;
		'q' =>	qflag++;
		'r' =>	rflag++;
		'v' =>	vflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args == 0)
		arg->usage();

	if(rflag) {
		err: string;
		(rcfg, err) = Rcfg.mk(prime, width, mod);
		if(err != nil)
			error("rabincfg: "+err);
	}

	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		error(sprint("dialing %s: %r", addr));
	say("have connection");

	fd := conn.dfd;
	session = Session.new(fd);
	if(session == nil)
		error(sprint("handshake: %r"));
	say("have handshake");

	vd: ref Vacdir;
	if(basescore != nil) {
		err: string;
		(vd, nil, err) = vac->openroot(session, *basescore);
		if(err != nil)
			error("opening base score: "+err);

		d := session.read(*basescore, Roottype, Venti->Rootsize);
		if(d == nil)
			error("reading base root block: "+err);
		r := Root.unpack(d);
		if(rflag && r.version != Venti->Rootversionvar || !rflag && r.version != Venti->Rootversion)
			error("old archive not of same type as new archive");
	}

	topde: ref Direntry;
	if(len args == 1 && ((nil, d) := sys->stat(hd args)).t0 == 0 && d.mode&Sys->DMDIR) {
		topde = Direntry.mk(d);
		topde.elem = name;
	} else {
		topde = Direntry.new();
		topde.elem = name;
		topde.uid = topde.gid = user();
		topde.mode = 8r777|Vac->Modedir;
		topde.mtime = topde.atime = 0;
	}
	topde.ctime = daytime->now();

	s := Sink.new(session, blocksize);
	ms := MSink.new(session, blocksize);
	for(; args != nil; args = tl args)
		writepath(hd args, s, ms, vd);
	say("tree written");

	e0 := s.finish();
	if(e0 == nil)
		error(sprint("writing top entry: %r"));
	e1 := ms.finish();
	if(e1 == nil)
		error(sprint("writing top meta entry: %r"));
	say(sprint("top entries written (%s, %s)", e0.score.text(), e1.score.text()));
	s2 := MSink.new(session, blocksize);
	if(s2.add(topde) < 0)
		error(sprint("adding direntry for top entries: %r"));
	e2 := s2.finish();
	say("top meta entry written, "+e2.score.text());

 	td := array[Entrysize*3] of byte;
 	td[0*Entrysize:] = e0.pack();
 	td[1*Entrysize:] = e1.pack();
 	td[2*Entrysize:] = e2.pack();
	(tok, tscore) := session.write(Dirtype, td);
	if(tok < 0)
		error(sprint("writing top-level entries: %r"));
	say("top entry written, "+tscore.text());

	root := Root.new(name, "vac", tscore, blocksize, nil);
	if(rflag) {
		root.version = Venti->Rootversionvar;
		root.blocksize = 0;
	}
	if(basescore != nil)
		root.prev = basescore;
	rd := root.pack();
	if(rd == nil)
		error(sprint("root pack: %r"));
	(rok, rscore) := session.write(Roottype, rd);
	if(rok < 0)
		error(sprint("writing root score: %r"));

	if(session.sync() < 0)
		error(sprint("syncing server: %r"));

	say("root written, "+rscore.text());
	print("%s:%s\n", root.rtype, rscore.text());
	if(vflag) {
		fprint(fildes(2), "%10bd %13bd blocks read/written\n", vac->blocksread, vac->blockswritten);
		fprint(fildes(2), "%10bd %13bd bytes read/written\n", vac->bytesread, vac->byteswritten);
	}
}

writepath(path: string, s: ref Sink, ms: ref MSink, vd: ref Vacdir)
{
	if(vflag)
		fprint(fildes(2), "%s\n", path);
say("writepath "+path);
	fd := sys->open(path, sys->OREAD);
	if(fd == nil)
		error(sprint("opening %s: %r", path));
	(ok, dir) := sys->fstat(fd);
	if(ok < 0)
		error(sprint("fstat %s: %r", path));
say("writepath: file opened");
	if(dir.mode&sys->DMAUTH) {
		fprint(fildes(2), "%s: is auth file, skipping", path);
		return;
	}
	if(dir.mode&sys->DMTMP) {
		fprint(fildes(2), "%s: is temporary file, skipping", path);
		return;
	}

	e, me: ref Entry;
	de: ref Direntry;
	if(dir.mode & sys->DMDIR) {
say("writepath: file is dir");
		ns := Sink.new(session, blocksize);
		nms := MSink.new(session, blocksize);

		nvd := vdopendir(vd, dir.name);
		for(;;) {
			(n, dirs) := sys->dirread(fd);
			if(n == 0)
				break;
			if(n < 0)
				error(sprint("dirread %s: %r", path));
			for(i := 0; i < len dirs; i++) {
				d := dirs[i];
				npath := path+"/"+d.name;
				writepath(npath, ns, nms, nvd);
			}
		}
		e = ns.finish();
		if(e == nil)
			error(sprint("error flushing dirsink for %s: %r", path));
		me = nms.finish();
		if(me == nil)
			error(sprint("error flushing metasink for %s: %r", path));
	} else {
say("writepath: file is normal file");
		nde: ref Direntry;
		if(vd != nil)
			nde = vd.walk(dir.name);
		if(nde != nil)
			(e, nil) = vd.open(nde);
		f: ref File;
		offset := big 0;
		if(e != nil && qflag
			&& (nde.mode&Vac->Modeappend)
			&& (dir.mode&Sys->DMAPPEND)
			&& nde.mtime < dir.mtime
			&& e.size < dir.length
			&& nde.qid == dir.qid.path
			&& nde.mcount < dir.qid.vers)
		{ 
			f = File.mkstate(session, e, rflag);
			offset = f.size;
		} else if(f == nil && e != nil
			&& (nde.mtime != dir.mtime
			|| e.size != dir.length
			|| nde.qid != dir.qid.path
			|| nde.mcount != dir.qid.vers))
			e = nil;
		if(f == nil && e == nil)
			f = File.new(session, Datatype, blocksize, rflag);
		
		if(f != nil) {
say("writepath: file has changed or is new, writing it");
			e = writefile(path, fd, f, offset);
			if(e == nil)
				error(sprint("error flushing filesink for %s: %r", path));
		}
	}
say("writepath: wrote path, "+e.score.text());

	de = Direntry.mk(dir);
say("writepath: have direntry");

	i := s.add(e);
	if(i < 0)
		error(sprint("adding entry to sink: %r"));
	mi := 0;
	if(me != nil)
		mi = s.add(me);
	if(mi < 0)
		error(sprint("adding mentry to sink: %r"));
	de.entry = i;
	de.mentry = mi;
	i = ms.add(de);
	if(i < 0)
		error(sprint("adding direntry to msink: %r"));
say("writepath done");
}

writefile(path: string, fd: ref Sys->FD, f: ref File, offset: big): ref Entry
{
	bio := bufio->fopen(fd, bufio->OREAD);
	if(bio == nil)
		error(sprint("bufio opening %s: %r", path));
	say(sprint("bufio opened path %s, offset=%bd", path, offset));
	bio.seek(offset, Bufio->SEEKSTART);

	rfile: ref Rfile;
	if(rflag) {
		err: string;
		(rfile, err) = rabin->open(rcfg, bio, blockmin, blockmax);
		if(err != nil)
			error(sprint("rabin open %s: %s", path, err));
	}

	for(;;) {
		if(rflag) {
			(d, nil, err) := rfile.read();
			if(err != nil)
				error(sprint("reading %s: %s", path, err));
			if(len d == 0)
				break;
			if(f.write(d) < 0)
				error(sprint("writing %s: %r", path));
		} else {
			buf := array[blocksize] of byte;
			n := 0;
			while(n < len buf) {
				want := len buf - n;
				have := bio.read(buf[n:], want);
				if(have == 0)
					break;
				if(have < 0)
					error(sprint("reading %s: %r", path));
				n += have;
			}
			say(sprint("have buf, length %d", n));

			if(f.write(buf[:n]) < 0)
				error(sprint("writing %s: %r", path));
			if(n != len buf)
				break;
		}
	}
	bio.close();
	return f.finish();
}

vdopendir(vd: ref Vacdir, elem: string): ref Vacdir
{
	if(vd == nil)
		return nil;
	de := vd.walk(elem);
	if(de == nil)
		return nil;
	(e, me) := vd.open(de);
	if(e == nil || me == nil)
		return nil;
	return Vacdir.new(session, e, me);
}

user(): string
{
	if((fd := sys->open("/dev/user", Sys->OREAD)) != nil
		&& (n := sys->read(fd, d := array[128] of byte, len d)) > 0)
		return string d[:n];
	return "nobody";
}

error(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}

say(s: string)
{
	if(Dflag)
		fprint(fildes(2), "%s\n", s);
}
