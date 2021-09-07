implement Vac;

include "sys.m";
include "string.m";
include "venti.m";
include "vac.m";

sys: Sys;
str: String;
venti: Venti;

werrstr, sprint, fprint, fildes: import sys;
Root, Rootsize, Entry, Entrysize, Roottype, Dirtype, Pointertype0, Datatype: import venti;
Pointervarmask, Entryactive, Entrydir, Entrydepthshift, Entrydepthmask, Entrylocal, Entryvarblocks: import venti;
Score, Session, Scoresize: import venti;

debug := 0;

BIT8SZ:	con 1;
BIT16SZ:        con 2;
BIT32SZ:        con 4;
BIT48SZ:        con 6;
BIT64SZ:	con 8;

Rootnamelen:	con 128;
Maxstringsize: con 1000;

blankroot: Root;
blankentry: Entry;
blankdirentry: Direntry;
blankmetablock: Metablock;
blankmetaentry: Metaentry;


init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	venti = load Venti Venti->PATH;
	venti->init();
}

vread(session: ref Session, s: Score, t: int, maxsize: int): array of byte
{
	d := session.read(s, t, maxsize);
	blocksread++;
	bytesread += big len d;
	return d;
}

vwrite(session: ref Session, t: int, d: array of byte): (int, Score)
{
	(ok, score) := session.write(t, d);
	blockswritten++;
	byteswritten += big len d;
	return (ok, score);
}

pstring(a: array of byte, o: int, s: string): int
{
	sa := array of byte s;	# could do conversion ourselves
	n := len sa;
	a[o] = byte (n >> 8);
	a[o+1] = byte n;
	a[o+2:] = sa;
	return o+BIT16SZ+n;
}

gstring(a: array of byte, o: int): (string, int)
{
	if(o < 0 || o+BIT16SZ > len a)
		return (nil, -1);
	l := (int a[o] << 8) | int a[o+1];
	if(l > Maxstringsize)
		return (nil, -1);
	o += BIT16SZ;
	e := o+l;
	if(e > len a)
		return (nil, -1);
	return (string a[o:e], e);
}

Direntry.new(): ref Direntry
{
	return ref Direntry(9, "", 0, 0, 0, 0, big 0, "", "", "", 0, 0, 0, 0, 0, 0);
}

Direntry.mk(d: Sys->Dir): ref Direntry
{
	atime := 0; # d.atime;
	mode := d.mode&Modeperm;
	if(d.mode&sys->DMAPPEND)
		mode |= Modeappend;
	if(d.mode&sys->DMEXCL)
		mode |= Modeexcl;
	if(d.mode&sys->DMDIR)
		mode |= Modedir;
	if(d.mode&sys->DMTMP)
		mode |= Modetemp;
	return ref Direntry(9, d.name, 0, 0, 0, 0, d.qid.path, d.uid, d.gid, d.muid, d.mtime, d.qid.vers, 0, atime, mode, d.mode);
}

Direntry.mkdir(de: self ref Direntry): ref Sys->Dir
{
        d := ref sys->nulldir;
        d.name = de.elem;
        d.uid = de.uid;
        d.gid = de.gid;
        d.muid = de.mid;
        d.qid.path = de.qid;
        d.qid.vers = 0;
        d.qid.qtype = de.emode>>24;
        d.mode = de.emode;
        d.atime = de.atime;
        d.mtime = de.mtime;
        d.length = big 0;
        return d;
}

strlen(s: string): int
{
	return 2+len array of byte s;
}

Direntry.pack(de: self ref Direntry): array of byte
{
	# assume version 9
	length := 4+2+strlen(de.elem)+4+4+4+4+8+strlen(de.uid)+strlen(de.gid)+strlen(de.mid)+4+4+4+4+4; # + qidspace?

	d := array[length] of byte;
	i := 0;
	i = p32(d, i, Direntrymagic);
	i = p16(d, i, de.version);
	i = pstring(d, i, de.elem);
	i = p32(d, i, de.entry);
	if(de.version == 9) {
		i = p32(d, i, de.gen);
		i = p32(d, i, de.mentry);
		i = p32(d, i, de.mgen);
	}
	i = p64(d, i, de.qid);
	i = pstring(d, i, de.uid);
	i = pstring(d, i, de.gid);
	i = pstring(d, i, de.mid);
	i = p32(d, i, de.mtime);
	i = p32(d, i, de.mcount);
	i = p32(d, i, de.ctime);
	i = p32(d, i, de.atime);
	i = p32(d, i, de.mode);
	if(i != len d) {
		werrstr(sprint("bad length for direntry (expected %d, have %d)", len d, i));
		return nil;
	}
	return d;
}

Direntry.unpack(d: array of byte): ref Direntry
{
	{
		de := ref blankdirentry;
		i := 0;
		magic: int;
		(magic, i) = eg32(d, i);
		if(magic != Direntrymagic) {
			werrstr(sprint("bad magic (%x, want %x)", magic, Direntrymagic));
			return nil;
		}
		(de.version, i) = eg16(d, i);
		if(de.version != 8 && de.version != 9) {
			werrstr(sprint("bad version (%d)", de.version));
			return nil;
		}
		(de.elem, i) = egstring(d, i);
		(de.entry, i) = eg32(d, i);
		case de.version {
		8 =>
			de.gen = 0;
			de.mentry = de.entry+1;
			de.mgen = 0;
		9 =>
			(de.gen, i) = eg32(d, i);
			(de.mentry, i) = eg32(d, i);
			(de.mgen, i) = eg32(d, i);
		}
		(de.qid, i) = eg64(d, i);
		(de.uid, i) = egstring(d, i);
		(de.gid, i) = egstring(d, i);
		(de.mid, i) = egstring(d, i);
		(de.mtime, i) = eg32(d, i);
		(de.mcount, i) = eg32(d, i);
		(de.ctime, i) = eg32(d, i);
		(de.atime, i) = eg32(d, i);
		(de.mode, i) = eg32(d, i);
		de.emode = de.mode&Modeperm;
		if(de.mode&Modeappend)
			de.emode |= sys->DMAPPEND;
		if(de.mode&Modeexcl)
			de.emode |= sys->DMEXCL;
		if(de.mode&Modedir)
			de.emode |= sys->DMDIR;
		if(de.mode&Modetemp)
			de.emode |= sys->DMTMP;
		if(de.version == 9)
			; # xxx handle qid space?, can be in here
		return de;
	} exception e {
	"too small:*" =>
		werrstr("direntry "+e);
		return nil;
	* =>
		raise e;
	}
}


Metablock.new(): ref Metablock
{
	return ref Metablock(0, 0, 0, 0);
}

Metablock.pack(mb: self ref Metablock, d: array of byte)
{
	i := 0;
	i = p32(d, i, Metablockmagic);
	i = p16(d, i, mb.size);
	i = p16(d, i, mb.free);
	i = p16(d, i, mb.maxindex);
	i = p16(d, i, mb.nindex);
}

Metablock.unpack(d: array of byte): ref Metablock
{
	if(len d < Metablocksize) {
		werrstr(sprint("bad length for metablock (%d, want %d)", len d, Metablocksize));
		return nil;
	}
	i := 0;
	magic := g32(d, i);
	if(magic != Metablockmagic && magic != Metablockmagic+1) {
		werrstr(sprint("bad magic for metablock (%x, need %x)", magic, Metablockmagic));
		return nil;
	}
	i += BIT32SZ;

	mb := ref blankmetablock;
	mb.size = g16(d, i);
	i += BIT16SZ;
	mb.free = g16(d, i);
	i += BIT16SZ;
	mb.maxindex = g16(d, i);
	i += BIT16SZ;
	mb.nindex = g16(d, i);
	i += BIT16SZ;
	if(mb.nindex == 0) {
		werrstr("bad metablock, nindex=0");
		return nil;
	}
	return mb;
}

Metaentry.pack(me: self ref Metaentry, d: array of byte)
{
	i := 0;
	i = p16(d, i, me.offset);
	i = p16(d, i, me.size);
}

Metaentry.unpack(d: array of byte, i: int): ref Metaentry
{
	o := Metablocksize+i*Metaentrysize;
	if(o+Metaentrysize > len d) {
		werrstr(sprint("meta entry lies outside meta block, i=%d", i));
		return nil;
	}

	me := ref blankmetaentry;
	me.offset = g16(d, o);
	o += BIT16SZ;
	me.size = g16(d, o);
	o += BIT16SZ;
	if(me.offset+me.size > len d) {
		werrstr(sprint("meta entry points outside meta block, i=%d", i));
		return nil;
	}
	return me;
}


Page.new(dsize: int, varblocks: int): ref Page
{
	esize := Scoresize;
	treesize := big 0;
	if(varblocks)
		esize += BIT64SZ;
	else
		treesize = ~big 0;
	psize := (dsize/esize)*esize;
	return ref Page(array[psize] of byte, 0, esize, treesize);
}

Page.npointers(p: self ref Page): int
{
	return p.o/p.esize;
}

Page.add(p: self ref Page, s: Score, size: big)
{
	p.d[p.o:] = s.a;
	p.o += Scoresize;
	if(p.treesize != ~big 0) {
		p64(p.d, p.o, size);
		p.o += BIT64SZ;
		p.treesize += size;
	}
}

Page.full(p: self ref Page): int
{
	return p.o+p.esize> len p.d;
}

Page.data(p: self ref Page): array of byte
{
	if(p.treesize != ~big 0)
		return p.d[:p.o];
	for(i := p.o; i >= Scoresize; i -= Scoresize)
		if(!Score(p.d[i-Scoresize:i]).eq(Score.zero()))
			break;
	return p.d[:i];
}


File.new(s: ref Session, dtype, dsize, varblocks: int): ref File
{
	p := array[1] of ref Page;
	p[0] = Page.new(dsize, varblocks);
	return ref File(p, dtype, dsize, big 0, s, varblocks);
}

fflush(f: ref File, last: int): (int, ref Entry)
{
	for(i := 0; i < len f.p; i++) {
		if(!last && !f.p[i].full())
			return (0, nil);
		if(last && f.p[i].npointers() == 1) {
			flags := Entryactive;
			flags |= i<<Entrydepthshift;
			if(f.dtype & Dirtype)
				flags |= Entrydir;
			if(f.varblocks)
				flags |= Entryvarblocks;
			d := f.p[i].data();
			if(len d == 0)
				d = Score.zero().a;
			d = d[:Scoresize];
			score := Score(d);
			dsize := f.dsize;
			if(f.varblocks)
				dsize = 0;
			return (0, Entry.new(len f.p[i].d, dsize, flags, f.size, score));
		}
		t := Pointertype0+i;
		if(f.varblocks)
			t |= Pointervarmask;
		(ok, score) := vwrite(f.s, t, f.p[i].data());
		if(ok < 0)
			return (-1, nil);
		treesize := f.p[i].treesize;
		f.p[i] = Page.new(f.dsize, f.varblocks);
		if(i+1 == len f.p) {
			newp := array[len f.p+1] of ref Page;
			newp[:] = f.p;
			newp[len newp-1] = Page.new(f.dsize, f.varblocks);
			f.p = newp;
		}
		f.p[i+1].add(score, treesize);
	}
	werrstr("internal error in fflush");
	return (-1, nil);
}

File.write(f: self ref File, d: array of byte): int
{
	(fok, nil) := fflush(f, 0);
	if(fok < 0)
		return -1;
	length := len d;
	for(i := len d; i > 0; i--)
		if(d[i-1] != byte 0)
			break;
	d = d[:i];
	(ok, score) := vwrite(f.s, f.dtype, d);
	if(ok < 0)
		return -1;
	f.size += big length;
	f.p[0].add(score, big length);
	return 0;
}

File.finish(f: self ref File): ref Entry
{
	(ok, e) := fflush(f, 1);
	if(ok < 0)
		return nil;
	return e;
}

File.mkstate(session: ref Venti->Session, e: ref Entry, varblocks: int): ref File
{
	s := e.score;
	dsize := e.dsize;
	if(dsize == 0)
		dsize = Venti->Dsize;	# xxx make configurable?  pointer block size is currently assumed to be Dsize everywhere
	if(e.depth == 0) {
		p := Page.new(dsize, varblocks);
		return ref File(array[1] of {p}, Datatype, dsize, big 0, session, varblocks);
	}
	f := ref File(array[e.depth] of ref Page, Datatype, dsize, big 0, session, varblocks);
	for(i := 0; i < e.depth; i++) {
		t := Pointertype0+e.depth-1-i;
		if(f.varblocks)
			t |= Pointervarmask;
		d := vread(session, s, t, Venti->Maxlumpsize);
		if(d == nil)
			return nil;
		p := Page.new(dsize, varblocks);
		p.d[:] = d;
		p.o = len d-p.esize;
		s = Score(p.d[p.o:p.o+Scoresize]);
		f.p[i] = p;
	}
	if(varblocks) {
		lp := f.p[len f.p-1];
		bsize := g64(lp.d, lp.o+Scoresize);
		f.size = e.size-bsize;
		for(i = 0; i < len f.p; i++)
			f.p[i].treesize -= bsize;
	} else {
		ls := e.size % big e.dsize;
		if(ls == big 0)
			ls = big e.dsize;
		f.size = e.size-ls;
	}
	return f;
}


Sink.new(s: ref Venti->Session, dsize: int): ref Sink
{
	dirdsize := (dsize/Entrysize)*Entrysize;
	return ref Sink(File.new(s, Dirtype, dsize, 0), array[dirdsize] of byte, 0, 0);
}

# xxx are we really allowed to split these entries?  i have a feeling we are not.
Sink.add(m: self ref Sink, e: ref Entry): int
{
	ed := e.pack();
	if(ed == nil)
		return -1;
	n := len m.d - m.nd;
	if(n > len ed)
		n = len ed;
	m.d[m.nd:] = ed[:n];
	m.nd += n;
	if(n < len ed) {
		if(m.f.write(m.d) < 0)
			return -1;
		m.nd = len ed - n;
		m.d[:] = ed[n:];
	}
	return m.ne++;
}

Sink.finish(m: self ref Sink): ref Entry
{
	if(m.nd > 0)
		if(m.f.write(m.d[:m.nd]) < 0)
			return nil;
	e := m.f.finish();
	e.dsize = len m.d;
	return e;
}


elemcmp(a, b: array of byte, fossil: int): int
{
	for(i := 0; i < len a && i < len b; i++)
		if(a[i] != b[i])
			return (int a[i] - int b[i]);
	if(fossil)
		return len a - len b;
	return len b - len a;
}

Mentry.cmp(a, b: ref Mentry): int
{
	return elemcmp(array of byte a.elem, array of byte b.elem, 0);
}

MSink.new(s: ref Venti->Session, dsize: int): ref MSink
{
	return ref MSink(File.new(s, Datatype, dsize, 0), array[dsize] of byte, 0, nil);
}

l2a[T](l: list of T): array of T
{
	a := array[len l] of T;
	i := 0;
	for(; l != nil; l = tl l)
		a[i++] = hd l;
	return a;
}

insertsort[T](a: array of T)
	for { T =>	cmp:	fn(a, b: T): int; }
{
	for(i := 1; i < len a; i++) {
		tmp := a[i];
		for(j := i; j > 0 && T.cmp(a[j-1], tmp) > 0; j--)
			a[j] = a[j-1];
		a[j] = tmp;
	}
}

mflush(m: ref MSink, last: int): int
{
	d := array[len m.de] of byte;

	me := l2a(m.l);
	insertsort(me);
	o := Metablocksize;
	deo := o+len m.l*Metaentrysize;
	for(i := 0; i < len me; i++) {
		me[i].me.offset += deo;
		me[i].me.pack(d[o:]);
		o += Metaentrysize;
	}
	d[o:] = m.de[:m.nde];
	o += m.nde;
	if(!last)
		while(o < len d)
			d[o++] = byte 0;

	mb := Metablock.new();
	mb.nindex = len m.l;
	mb.maxindex = mb.nindex;
	mb.free = 0;
	mb.size = o;
	mb.pack(d);

	if(m.f.write(d[:o]) < 0)
		return -1;
	m.nde = 0;
	m.l = nil;
	return 0;
}

MSink.add(m: self ref MSink, de: ref Direntry): int
{
	d := de.pack();
	if(d == nil)
		return -1;
	if(Metablocksize+len m.l*Metaentrysize+m.nde + Metaentrysize+len d > len m.de)
		if(mflush(m, 0) < 0)
			return -1;
	m.de[m.nde:] = d;
	m.l = ref Mentry(de.elem, ref Metaentry(m.nde, len d))::m.l;
	m.nde += len d;
	return 0;
}

MSink.finish(m: self ref MSink): ref Entry
{
	if(m.nde > 0)
		mflush(m, 1);
	return m.f.finish();
}

Source.new(s: ref Session, e: ref Entry): ref Source
{
	return ref Source(s, e);
}

power(b, e: int): big
{
	r := big 1;
	while(e-- > 0)
		r *= big b;
	return r;
}

blocksize(e: ref Entry): int
{
	if(e.psize > e.dsize)
		return e.psize;
	return e.dsize;
}

Source.get(s: self ref Source, i: big, d: array of byte): int
{
	npages := (s.e.size+big (s.e.dsize-1))/big s.e.dsize;
	if(i*big s.e.dsize >= s.e.size)
		return 0;

	want := s.e.dsize;
	if(i == npages-big 1)
		want = int (s.e.size - i*big s.e.dsize);
	last := s.e.score;
	bsize := blocksize(s.e);
	buf: array of byte;

	npp := s.e.psize/Scoresize;	# scores per pointer block
	np := power(npp, s.e.depth-1);	# blocks referenced by score at this depth
	for(depth := s.e.depth; depth >= 0; depth--) {
		dtype := Pointertype0+depth-1;
		if(depth == 0) {
			dtype = Datatype;
			if(s.e.flags & Entrydir)
				dtype = Dirtype;
			bsize = want;
		}
		buf = vread(s.session, last, dtype, bsize);
		if(buf == nil)
			return -1;
		if(depth > 0) {
			pi := int (i / np);
			i %= np;
			np /= big npp;
			o := (pi+1)*Scoresize;
			if(o <= len buf)
				last = Score(buf[o-Scoresize:o]);
			else
				last = Score.zero();
		}
	}
	for(j := len buf; j < want; j++)
		d[j] = byte 0;
	d[:] = buf;
	return want;
}

Source.oget(s: self ref Source, offset: big): array of byte
{
	if(offset >= s.e.size)
		return array[0] of byte;

	coffset := big 0;
	esize := Scoresize;
	if(s.e.flags&Entryvarblocks)
		esize += 8;
	last := s.e.score;
	tlen := s.e.size;

	for(depth := s.e.depth; depth > 0; depth--) {
		dtype := Pointertype0+depth-1;
		dtype |= Pointervarmask;
		buf := vread(s.session, last, dtype, s.e.psize);
		if(buf == nil)
			return nil;

		(last, tlen) = (Score(buf[:Scoresize]), g64(buf, Scoresize));
		for(o := esize; o+esize <= len buf; o += esize) {
			if(offset < coffset+tlen)
				break;
			coffset += tlen;
			tlen = g64(buf, o+Scoresize);
			last = Score(buf[o:o+Scoresize]);
		}
		if(coffset+tlen < offset || coffset > offset) {
			sys->werrstr("bad source.oget");
			return nil;
		}
	}
	buf := vread(s.session, last, Datatype, int tlen);
	if(buf == nil)
		return nil;
	if(len buf != int tlen) {
		sys->werrstr(sprint("unexpected block size, score=%s, want=%d have=%d", last.text(), int tlen, len buf));
		return nil;
	}
	return buf[int (offset-coffset):];
}


Vacfile.mk(s: ref Source): ref Vacfile
{
	return ref Vacfile(s, big 0);
}

Vacfile.new(s: ref Session, e: ref Entry): ref Vacfile
{
	return Vacfile.mk(Source.new(s, e));
}

Vacfile.seek(v: self ref Vacfile, offset: big): big
{
	v.o += offset;
	if(v.o > v.s.e.size)
		v.o = v.s.e.size;
	return v.o;
}

Vacfile.read(v: self ref Vacfile, d: array of byte, n: int): int
{
	have := v.pread(d, n, v.o);
	if(have > 0)
		v.o += big have;
	return have;
}

Vacfile.pread(v: self ref Vacfile, d: array of byte, n: int, offset: big): int
{
	if(v.s.e.flags&Entryvarblocks) {
		buf := v.s.oget(offset);
		if(buf == nil)
			return -1;
		if(len buf < n)
			n = len buf;
		d[:] = buf[:n];
		return n;
	} else {
		dsize := v.s.e.dsize;
		have := v.s.get(big (offset/big dsize), buf := array[dsize] of byte);
		if(have <= 0)
			return have;
		o := int (offset % big dsize);
		have -= o;
		if(have > n)
			have = n;
		if(have <= 0)
			return 0;
		d[:] = buf[o:o+have];
		return have;
	}
}


Vacdir.mk(vf: ref Vacfile, ms: ref Source): ref Vacdir
{
	return ref Vacdir(vf, ms, big 0, 0);
}

Vacdir.new(session: ref Session, e, me: ref Entry): ref Vacdir
{
        vf := Vacfile.new(session, e);
        ms := Source.new(session, me);
        return Vacdir.mk(vf, ms);

}

mecmp(d: array of byte, i: int, elem: string, fromfossil: int): (int, int)
{
	me := Metaentry.unpack(d, i);
	if(me == nil)
		return (0, 1);
	o := me.offset+6;
	n := g16(d, o);
	o += BIT16SZ;
	if(o+n > len d) {
		werrstr("bad elem in direntry");
		return (0, 1);
	}
	return (elemcmp(d[o:o+n], array of byte elem, fromfossil), 0);
}

finddirentry(d: array of byte, elem: string): (int, ref Direntry)
{
	mb := Metablock.unpack(d);
	if(mb == nil)
		return (-1, nil);
	fromfossil := g32(d, 0) == Metablockmagic+1;

        left := 0;
        right := mb.nindex;
	while(left+1 != right) {
                mid := (left+right)/2;
		(c, err) := mecmp(d, mid, elem, fromfossil);
		if(err)
			return (-1, nil);
		if(c <= 0)
			left = mid;
		else
			right = mid;
		if(c == 0)
			break;
        }
	de := readdirentry(d, left);
	if(de != nil && de.elem == elem)
		return (1, de);
	return (0, nil);
}

Vacdir.walk(v: self ref Vacdir, elem: string): ref Direntry
{
	i := big 0;
	for(;;) {
		n := v.ms.get(i, buf := array[v.ms.e.dsize] of byte);
		if(n < 0)
			return nil;
		if(n == 0)
			break;
		(ok, de) := finddirentry(buf[:n], elem);
		if(ok < 0)
			return nil;
		if(de != nil)
			return de;
		i++;
	}
	werrstr(sprint("no such file or directory"));
	return nil;
}

vfreadentry(vf: ref Vacfile, entry: int): ref Entry
{
	ebuf := array[Entrysize] of byte;
	n := vf.pread(ebuf, len ebuf, big entry*big Entrysize);
	if(n < 0)
		return nil;
	if(n != len ebuf) {
		werrstr(sprint("bad archive, entry=%d not present", entry));
		return nil;
	}
	e := Entry.unpack(ebuf);
	if(~e.flags&Entryactive) {
		werrstr("entry not active");
		return nil;
	}
	if(e.flags&Entrylocal) {
		werrstr("entry is local");
		return nil;
	}
	return e;
}

Vacdir.open(vd: self ref Vacdir, de: ref Direntry): (ref Entry, ref Entry)
{
	e := vfreadentry(vd.vf, de.entry);
	if(e == nil)
		return (nil, nil);
	isdir1 := de.mode & Modedir;
	isdir2 := e.flags & Entrydir;
	if(isdir1 && !isdir2 || !isdir1 && isdir2) {
		werrstr("direntry directory bit does not match entry directory bit");
		return (nil, nil);
	}
	me: ref Entry;
	if(de.mode&Modedir) {
		me = vfreadentry(vd.vf, de.mentry);
		if(me == nil)
			return (nil, nil);
	}
	return (e, me);
}

readdirentry(buf: array of byte, i: int): ref Direntry
{
	me := Metaentry.unpack(buf, i);
	if(me == nil)
		return nil;
	o := me.offset;
	de := Direntry.unpack(buf[o:o+me.size]);
	if(badelem(de.elem)) {
		werrstr(sprint("bad direntry: %s", de.elem));
		return nil;
	}
	return de;
}
	
has(c: int, s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return 1;
	return 0;
}

badelem(elem: string): int
{
	return elem == "" || elem == "." || elem == ".." || has('/', elem) || has(0, elem);
}

Vacdir.readdir(vd: self ref Vacdir): (int, ref Direntry)
{
	dsize := vd.ms.e.dsize;
	n := vd.ms.get(vd.p, buf := array[dsize] of byte);
	if(n <= 0)
		return (n, nil);
	mb := Metablock.unpack(buf);
	if(mb == nil)
		return (-1, nil);
	de := readdirentry(buf, vd.i);
	if(de == nil)
		return (-1, nil);
	vd.i++;
	if(vd.i >= mb.nindex) {
		vd.p++;
		vd.i = 0;
	}
	return (1, de);
}

Vacdir.rewind(vd: self ref Vacdir)
{
	vd.p = big 0;
	vd.i = 0;
}


openroot(session: ref Session, score: Venti->Score): (ref Vacdir, ref Direntry, string)
{
	d := vread(session, score, Roottype, Rootsize);
	if(d == nil)
		return (nil, nil, sprint("reading vac score: %r"));
	r := Root.unpack(d);
	if(r == nil)
		return (nil, nil, sprint("bad vac root block: %r"));
	say("have root");
	topscore := r.score;

	d = vread(session, topscore, Dirtype, 3*Entrysize);
	if(d == nil)
		return (nil, nil, sprint("reading rootdir score: %r"));
	if(len d != 3*Entrysize) {
		say("top entries not in directory of 3 elements, assuming it's from fossil");
		if(len d % Entrysize != 0 && len d == 2*Entrysize != 0)	# what's in the second 40 bytes?  looks like 2nd 20 bytes of it is zero score
			return (nil, nil, sprint("bad fossil rootdir, have %d bytes, need %d or %d", len d, Entrysize, 2*Entrysize));
		e := Entry.unpack(d[:Entrysize]);
		if(e == nil)
			return (nil, nil, sprint("unpacking fossil top-level entry: %r"));
		topscore = e.score;
		d = vread(session, topscore, Dirtype, 3*Entrysize);
		if(d == nil)
			return (nil, nil, sprint("reading fossil rootdir block: %r"));
		say("have fossil top entries");
	}
	say("have top entries");

	e := array[3] of ref Entry;
	j := 0;
	for(i := 0; i+Entrysize <= len d; i += Entrysize) {
		e[j] = Entry.unpack(d[i:i+Entrysize]);
		if(e[j] == nil)
			return (nil, nil, sprint("reading root entry %d: %r", j));
		j++;
	}
	say("top entries unpacked");

	mroot := Vacdir.new(session, nil, e[2]);
	(ok, de) := mroot.readdir();
	if(ok <= 0)
		return (nil, nil, sprint("reading root meta entry: %r"));

say(sprint("openroot: new score=%s", score.text()));
	return (Vacdir.new(session, e[0], e[1]), de, nil);
}

readscore(path: string): (string, ref Venti->Score, string)
{
	f := sys->open(path, Sys->OREAD);
	if(f == nil)
		return (nil, nil, sprint("open: %r"));
	n := sys->read(f, d := array[Rootnamelen+1+2*Scoresize+1] of byte, len d);
	if(n < 0)
		return (nil, nil, sprint("read: %r"));

	(tag, scorestr) := str->splitstrr(string d[:n], ":");
	if(tag != nil)
		tag = tag[:len tag-1];
	if(tag != "vac")
		return (nil, nil, "unknown score type: "+tag);
	if(len scorestr == 2*Scoresize+1)
		scorestr = scorestr[:len scorestr-1];
	(ok, s) := Score.parse(scorestr);
	if(ok != 0)
		return (nil, nil, "bad score: "+scorestr);
	return (tag, ref s, nil);
}

g16(f: array of byte, i: int): int
{
	return (int f[i] << 8) | int f[i+1];
}

g32(f: array of byte, i: int): int
{
	return (((((int f[i+0] << 8) | int f[i+1]) << 8) | int f[i+2]) << 8) | int f[i+3];
}

g48(f: array of byte, i: int): big
{
	b1 := (((((int f[i+0] << 8) | int f[i+1]) << 8) | int f[i+2]) << 8) | int f[i+3];
	b0 := (int f[i+4] << 8) | int f[i+5];
	return (big b1 << 16) | big b0;
}

g64(f: array of byte, i: int): big
{
	b0 := (((((int f[i+0] << 8) | int f[i+1]) << 8) | int f[i+2]) << 8) | int f[i+3];
	b1 := (((((int f[i+4] << 8) | int f[i+5]) << 8) | int f[i+6]) << 8) | int f[i+7];
	return (big b0 << 32) | (big b1 & 16rFFFFFFFF);
}

p16(d: array of byte, i: int, v: int): int
{
	d[i+0] = byte (v>>8);
	d[i+1] = byte v;
	return i+BIT16SZ;
}

p32(d: array of byte, i: int, v: int): int
{
	p16(d, i+0, v>>16);
	p16(d, i+2, v);
	return i+BIT32SZ;
}

p48(d: array of byte, i: int, v: big): int
{
	p16(d, i+0, int (v>>32));
	p32(d, i+2, int v);
	return i+BIT48SZ;
}

p64(d: array of byte, i: int, v: big): int
{
	p32(d, i+0, int (v>>32));
	p32(d, i+4, int v);
	return i+BIT64SZ;
}

echeck(f: array of byte, i: int, l: int)
{
	if(i+l > len f)
		raise sprint("too small: buffer length is %d, requested %d bytes starting at offset %d", len f, l, i);
}

egstring(a: array of byte, o: int): (string, int)
{
	(s, no) := gstring(a, o);
	if(no == -1)
		raise sprint("too small: string runs outside buffer (length %d)", len a);
	return (s, no);
}

eg16(f: array of byte, i: int): (int, int)
{
	echeck(f, i, BIT16SZ);
	return (g16(f, i), i+BIT16SZ);
}

eg32(f: array of byte, i: int): (int, int)
{
	echeck(f, i, BIT32SZ);
	return (g32(f, i), i+BIT32SZ);
}

eg48(f: array of byte, i: int): (big, int)
{
	echeck(f, i, BIT48SZ);
	return (g48(f, i), i+BIT48SZ);
}

eg64(f: array of byte, i: int): (big, int)
{
	echeck(f, i, BIT64SZ);
	return (g64(f, i), i+BIT64SZ);
}

say(s: string)
{
	if(debug)
		fprint(fildes(2), "%s\n", s);
}
