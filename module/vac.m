Vac: module {
	PATH:	con "/dis/lib/vac.dis";
	init:	fn();

	blocksread, blockswritten, bytesread, byteswritten: big;

	# mode bits
	Modeperm: con 8r777;
	Modesticky,
	Modesetuid,
	Modesetgid,
	Modeappend,
	Modeexcl,
	Modesymlink,
	Modedir,
	Modehidden,
	Modesystem,
	Modearchive,
	Modetemp,
	Modesnapshot,
	Modedev,
	Modenamedpipe: con 1<<(9+iota);

	Metablocksize:	con 12;
	Metaentrysize:	con 4;

	Direntrymagic:	con 16r1c4d9072;
	Metablockmagic:	con 16r5656fc79;

	# parameters for writing rabin fingerprinted archives
	Rabinprime:	con 269;
	Rabinmod:	con 8*1024;
	Rabinwidth:	con 31;
	Rabinblockmin:	con 1024;
	Rabinblockmax:	con 32*1024;

	Direntry: adt {
		version:	int;
		elem:	string;
		entry, gen:	int;
		mentry, mgen:	int;
		qid:	big;
		uid, gid, mid:	string;
		mtime, mcount, ctime, atime, mode, emode: int;

		new:	fn(): ref Direntry;
		mk:	fn(d: Sys->Dir): ref Direntry;
		mkdir:	fn(de: self ref Direntry): ref Sys->Dir;
		pack:	fn(de: self ref Direntry): array of byte;
		unpack:	fn(d: array of byte): ref Direntry;
	};

	Metablock: adt {
		size, free, maxindex, nindex:	int;

		new:	fn(): ref Metablock;
		pack:	fn(mb: self ref Metablock, d: array of byte);
		unpack:	fn(d: array of byte): ref Metablock;
	};

	Metaentry: adt {
		offset, size:	int;

		pack:	fn(me: self ref Metaentry, d: array of byte);
		unpack:	fn(d: array of byte, i: int): ref Metaentry;
	};

	# single block
	Page: adt {
		d:	array of byte;
		o:	int;
		esize:	int;
		treesize:	big;

		new:	fn(dsize: int, varblocks: int): ref Page;
		npointers:	fn(p: self ref Page): int;
		add:	fn(p: self ref Page, s: Venti->Score, size: big);
		full:	fn(p: self ref Page): int;
		data:	fn(p: self ref Page): array of byte;
	};

	# for writing a hash tree file
	File: adt {
		p:	array of ref Page;
		dtype, dsize:	int;
		size:	big;
		s:	ref Venti->Session;
		varblocks:	int;

		new:	fn(s: ref Venti->Session, dtype, dsize, varblocks: int): ref File;
		write:	fn(f: self ref File, d: array of byte): int;
		finish:	fn(f: self ref File): ref Venti->Entry;
		mkstate:	fn(session: ref Venti->Session, e: ref Venti->Entry, varblocks: int): ref File;
	};

	# for writing venti directories (entries)
	Sink: adt {
		f:	ref File;
		d:	array of byte;
		nd, ne:	int;

		new:	fn(s: ref Venti->Session, dsize: int): ref Sink;
		add:	fn(m: self ref Sink, e: ref Venti->Entry): int;
		finish:	fn(m: self ref Sink): ref Venti->Entry;
	};

	Mentry: adt {
		elem:	string;
		me:	ref Metaentry;

		cmp:	fn(a, b: ref Mentry): int;
	};

	# for writing directory entries (meta blocks, meta entries, direntries)
	MSink: adt {
		f: 	ref File;
		de:	array of byte;
		nde:	int;
		l:	list of ref Mentry;

		new:	fn(s: ref Venti->Session, dsize: int): ref MSink;
		add:	fn(m: self ref MSink, de: ref Direntry): int;
		finish:	fn(m: self ref MSink): ref Venti->Entry;
	};

	# for reading pages from a hash tree referenced by an entry
	Source: adt {
		session:	ref Venti->Session;
		e:	ref Venti->Entry;

		new:	fn(s: ref Venti->Session, e: ref Venti->Entry): ref Source;
		get:	fn(s: self ref Source, i: big, d: array of byte): int;
		oget:	fn(s: self ref Source, offset: big): array of byte;
	};

	# for reading from a hash tree while keeping offset
	Vacfile: adt {
		s:	ref Source;
		o:	big;

		mk:	fn(s: ref Source): ref Vacfile;
		new:	fn(session: ref Venti->Session, e: ref Venti->Entry): ref Vacfile;
		read:	fn(v: self ref Vacfile, d: array of byte, n: int): int;
		seek:	fn(v: self ref Vacfile, offset: big): big;
		pread:	fn(v: self ref Vacfile, d: array of byte, n: int, offset: big): int;
	};

	# for listing contents of a vac directory and walking to path elements
	Vacdir: adt {
		vf:	ref Vacfile;
		ms:	ref Source;
		p:	big;
		i:	int;

		mk:	fn(vf: ref Vacfile, ms: ref Source): ref Vacdir;
		new:	fn(session: ref Venti->Session, e, me: ref Venti->Entry): ref Vacdir;
		walk:	fn(v: self ref Vacdir, elem: string): ref Direntry;
		open:	fn(v: self ref Vacdir, de: ref Direntry): (ref Venti->Entry, ref Venti->Entry);
		readdir:	fn(v: self ref Vacdir): (int, ref Direntry);
		rewind:		fn(v: self ref Vacdir);
	};

	openroot:	fn(session: ref Venti->Session, score: Venti->Score): (ref Vacdir, ref Direntry, string);
	readscore:	fn(path: string): (string, ref Venti->Score, string);
};
