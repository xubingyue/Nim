#
#
#            Nimrod's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## The ``tables`` module implements an efficient hash table that is
## a mapping from keys to values.
##
## If you are using simple standard types like ``int`` or ``string`` for the
## keys of the table you won't have any problems, but as soon as you try to use
## a more complex object as a key you will be greeted by a strange compiler
## error::
##
##   Error: type mismatch: got (Person)
##   but expected one of:
##   hashes.hash(x: openarray[A]): THash
##   hashes.hash(x: int): THash
##   hashes.hash(x: float): THash
##   …
##
## What is happening here is that the types used for table keys require to have
## a ``hash()`` proc which will convert them to a `THash <hashes.html#THash>`_
## value, and the compiler is listing all the hash functions it knows. After
## you add such a proc for your custom type everything will work. See this
## example:
##
## .. code-block:: nimrod
##   type
##     Person = object
##       firstName, lastName: string
##
##   proc hash(x: Person): THash =
##     ## Piggyback on the already available string hash proc.
##     ##
##     ## Without this proc nothing works!
##     result = x.firstName.hash !& x.lastName.hash
##     result = !$result
##
##   var
##     salaries = initTable[Person, int]()
##     p1, p2: Person
##
##   p1.firstName = "Jon"
##   p1.lastName = "Ross"
##   salaries[p1] = 30_000
##
##   p2.firstName = "소진"
##   p2.lastName = "박"
##   salaries[p2] = 45_000
##
## **Note:** The data types declared here have *value semantics*: This means
## that ``=`` performs a copy of the hash table.

import
  hashes, math

{.pragma: myShallow.}

type
  TSlotEnum = enum seEmpty, seFilled, seDeleted
  TKeyValuePair[A, B] = tuple[slot: TSlotEnum, key: A, val: B]
  TKeyValuePairSeq[A, B] = seq[TKeyValuePair[A, B]]
  TTable* {.final, myShallow.}[A, B] = object ## generic hash table
    data: TKeyValuePairSeq[A, B]
    counter: int
  PTable*[A,B] = ref TTable[A, B]

when not defined(nimhygiene):
  {.pragma: dirty.}

proc len*[A, B](t: TTable[A, B]): int =
  ## returns the number of keys in `t`.
  result = t.counter

iterator pairs*[A, B](t: TTable[A, B]): tuple[key: A, val: B] =
  ## iterates over any (key, value) pair in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield (t.data[h].key, t.data[h].val)

iterator mpairs*[A, B](t: var TTable[A, B]): tuple[key: A, val: var B] =
  ## iterates over any (key, value) pair in the table `t`. The values
  ## can be modified.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield (t.data[h].key, t.data[h].val)

iterator keys*[A, B](t: TTable[A, B]): A =
  ## iterates over any key in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield t.data[h].key

iterator values*[A, B](t: TTable[A, B]): B =
  ## iterates over any value in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield t.data[h].val

iterator mvalues*[A, B](t: var TTable[A, B]): var B =
  ## iterates over any value in the table `t`. The values can be modified.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield t.data[h].val

const
  growthFactor = 2

proc mustRehash(length, counter: int): bool {.inline.} =
  assert(length > counter)
  result = (length * 2 < counter * 3) or (length - counter < 4)

proc nextTry(h, maxHash: THash): THash {.inline.} =
  result = ((5 * h) + 1) and maxHash

template rawGetImpl() {.dirty.} =
  var h: THash = hash(key) and high(t.data) # start with real hash value
  while t.data[h].slot != seEmpty:
    if t.data[h].key == key and t.data[h].slot == seFilled:
      return h
    h = nextTry(h, high(t.data))
  result = -1

template rawInsertImpl() {.dirty.} =
  var h: THash = hash(key) and high(data)
  while data[h].slot == seFilled:
    h = nextTry(h, high(data))
  data[h].key = key
  data[h].val = val
  data[h].slot = seFilled

proc rawGet[A, B](t: TTable[A, B], key: A): int =
  rawGetImpl()

proc `[]`*[A, B](t: TTable[A, B], key: A): B =
  ## retrieves the value at ``t[key]``. If `key` is not in `t`,
  ## default empty value for the type `B` is returned
  ## and no exception is raised. One can check with ``hasKey`` whether the key
  ## exists.
  var index = rawGet(t, key)
  if index >= 0: result = t.data[index].val

proc mget*[A, B](t: var TTable[A, B], key: A): var B =
  ## retrieves the value at ``t[key]``. The value can be modified.
  ## If `key` is not in `t`, the ``EInvalidKey`` exception is raised.
  var index = rawGet(t, key)
  if index >= 0: result = t.data[index].val
  else: raise newException(EInvalidKey, "key not found: " & $key)

proc hasKey*[A, B](t: TTable[A, B], key: A): bool =
  ## returns true iff `key` is in the table `t`.
  result = rawGet(t, key) >= 0

proc rawInsert[A, B](t: var TTable[A, B], data: var TKeyValuePairSeq[A, B],
                     key: A, val: B) =
  rawInsertImpl()

proc enlarge[A, B](t: var TTable[A, B]) =
  var n: TKeyValuePairSeq[A, B]
  newSeq(n, len(t.data) * growthFactor)
  for i in countup(0, high(t.data)):
    if t.data[i].slot == seFilled: rawInsert(t, n, t.data[i].key, t.data[i].val)
  swap(t.data, n)

template addImpl() {.dirty.} =
  if mustRehash(len(t.data), t.counter): enlarge(t)
  rawInsert(t, t.data, key, val)
  inc(t.counter)

template putImpl() {.dirty.} =
  var index = rawGet(t, key)
  if index >= 0:
    t.data[index].val = val
  else:
    addImpl()

when false:
  # not yet used:
  template hasKeyOrPutImpl() {.dirty.} =
    var index = rawGet(t, key)
    if index >= 0:
      t.data[index].val = val
      result = true
    else:
      if mustRehash(len(t.data), t.counter): enlarge(t)
      rawInsert(t, t.data, key, val)
      inc(t.counter)
      result = false

proc `[]=`*[A, B](t: var TTable[A, B], key: A, val: B) =
  ## puts a (key, value)-pair into `t`.
  putImpl()

proc add*[A, B](t: var TTable[A, B], key: A, val: B) =
  ## puts a new (key, value)-pair into `t` even if ``t[key]`` already exists.
  addImpl()
  
proc del*[A, B](t: var TTable[A, B], key: A) =
  ## deletes `key` from hash table `t`.
  let index = rawGet(t, key)
  if index >= 0:
    t.data[index].slot = seDeleted
    dec(t.counter)

proc initTable*[A, B](initialSize=64): TTable[A, B] =
  ## creates a new hash table that is empty.
  ##
  ## `initialSize` needs to be a power of two. If you need to accept runtime
  ## values for this you could use the ``nextPowerOfTwo`` proc from the
  ## `math <math.html>`_ module.
  assert isPowerOfTwo(initialSize)
  result.counter = 0
  newSeq(result.data, initialSize)

proc toTable*[A, B](pairs: openArray[tuple[key: A, 
                    val: B]]): TTable[A, B] =
  ## creates a new hash table that contains the given `pairs`.
  result = initTable[A, B](nextPowerOfTwo(pairs.len+10))
  for key, val in items(pairs): result[key] = val

template dollarImpl(): stmt {.dirty.} =
  if t.len == 0:
    result = "{:}"
  else:
    result = "{"
    for key, val in pairs(t):
      if result.len > 1: result.add(", ")
      result.add($key)
      result.add(": ")
      result.add($val)
    result.add("}")

proc `$`*[A, B](t: TTable[A, B]): string =
  ## The `$` operator for hash tables.
  dollarImpl()
  
template equalsImpl() =
  if s.counter == t.counter:
    # different insertion orders mean different 'data' seqs, so we have
    # to use the slow route here:
    for key, val in s:
      if not hasKey(t, key): return false
      if t[key] != val: return false
    return true
  
proc `==`*[A, B](s, t: TTable[A, B]): bool =
  equalsImpl()
  
proc indexBy*[A, B, C](collection: A, index: proc(x: B): C): TTable[C, B] =
  ## Index the collection with the proc provided.
  # TODO: As soon as supported, change collection: A to collection: A[B]
  result = initTable[C, B]()
  for item in collection:
    result[index(item)] = item

proc len*[A, B](t: PTable[A, B]): int =
  ## returns the number of keys in `t`.
  result = t.counter

iterator pairs*[A, B](t: PTable[A, B]): tuple[key: A, val: B] =
  ## iterates over any (key, value) pair in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield (t.data[h].key, t.data[h].val)

iterator mpairs*[A, B](t: PTable[A, B]): tuple[key: A, val: var B] =
  ## iterates over any (key, value) pair in the table `t`. The values
  ## can be modified.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield (t.data[h].key, t.data[h].val)

iterator keys*[A, B](t: PTable[A, B]): A =
  ## iterates over any key in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield t.data[h].key

iterator values*[A, B](t: PTable[A, B]): B =
  ## iterates over any value in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield t.data[h].val

iterator mvalues*[A, B](t: PTable[A, B]): var B =
  ## iterates over any value in the table `t`. The values can be modified.
  for h in 0..high(t.data):
    if t.data[h].slot == seFilled: yield t.data[h].val

proc `[]`*[A, B](t: PTable[A, B], key: A): B =
  ## retrieves the value at ``t[key]``. If `key` is not in `t`,
  ## default empty value for the type `B` is returned
  ## and no exception is raised. One can check with ``hasKey`` whether the key
  ## exists.
  result = t[][key]

proc mget*[A, B](t: PTable[A, B], key: A): var B =
  ## retrieves the value at ``t[key]``. The value can be modified.
  ## If `key` is not in `t`, the ``EInvalidKey`` exception is raised.
  t[].mget(key)

proc hasKey*[A, B](t: PTable[A, B], key: A): bool =
  ## returns true iff `key` is in the table `t`.
  result = t[].hasKey(key)

proc `[]=`*[A, B](t: PTable[A, B], key: A, val: B) =
  ## puts a (key, value)-pair into `t`.
  t[][key] = val

proc add*[A, B](t: PTable[A, B], key: A, val: B) =
  ## puts a new (key, value)-pair into `t` even if ``t[key]`` already exists.
  t[].add(key, val)
  
proc del*[A, B](t: PTable[A, B], key: A) =
  ## deletes `key` from hash table `t`.
  t[].del(key)

proc newTable*[A, B](initialSize=64): PTable[A, B] =
  new(result)
  result[] = initTable[A, B](initialSize)

proc newTable*[A, B](pairs: openArray[tuple[key: A, 
                    val: B]]): PTable[A, B] =
  ## creates a new hash table that contains the given `pairs`.
  new(result)
  result[] = toTable[A, B](pairs)

proc `$`*[A, B](t: PTable[A, B]): string =
  ## The `$` operator for hash tables.
  dollarImpl()

proc `==`*[A, B](s, t: PTable[A, B]): bool =
  equalsImpl()

proc newTableFrom*[A, B, C](collection: A, index: proc(x: B): C): PTable[C, B] =
  ## Index the collection with the proc provided.
  # TODO: As soon as supported, change collection: A to collection: A[B]
  result = newTable[C, B]()
  for item in collection:
    result[index(item)] = item

# ------------------------------ ordered table ------------------------------

type
  TOrderedKeyValuePair[A, B] = tuple[
    slot: TSlotEnum, next: int, key: A, val: B]
  TOrderedKeyValuePairSeq[A, B] = seq[TOrderedKeyValuePair[A, B]]
  TOrderedTable* {.
      final, myShallow.}[A, B] = object ## table that remembers insertion order
    data: TOrderedKeyValuePairSeq[A, B]
    counter, first, last: int
  POrderedTable*[A, B] = ref TOrderedTable[A, B]

proc len*[A, B](t: TOrderedTable[A, B]): int {.inline.} =
  ## returns the number of keys in `t`.
  result = t.counter

template forAllOrderedPairs(yieldStmt: stmt) {.dirty, immediate.} =
  var h = t.first
  while h >= 0:
    var nxt = t.data[h].next
    if t.data[h].slot == seFilled: yieldStmt
    h = nxt

iterator pairs*[A, B](t: TOrderedTable[A, B]): tuple[key: A, val: B] =
  ## iterates over any (key, value) pair in the table `t` in insertion
  ## order.
  forAllOrderedPairs:
    yield (t.data[h].key, t.data[h].val)

iterator mpairs*[A, B](t: var TOrderedTable[A, B]): tuple[key: A, val: var B] =
  ## iterates over any (key, value) pair in the table `t` in insertion
  ## order. The values can be modified.
  forAllOrderedPairs:
    yield (t.data[h].key, t.data[h].val)

iterator keys*[A, B](t: TOrderedTable[A, B]): A =
  ## iterates over any key in the table `t` in insertion order.
  forAllOrderedPairs:
    yield t.data[h].key

iterator values*[A, B](t: TOrderedTable[A, B]): B =
  ## iterates over any value in the table `t` in insertion order.
  forAllOrderedPairs:
    yield t.data[h].val

iterator mvalues*[A, B](t: var TOrderedTable[A, B]): var B =
  ## iterates over any value in the table `t` in insertion order. The values
  ## can be modified.
  forAllOrderedPairs:
    yield t.data[h].val

proc rawGet[A, B](t: TOrderedTable[A, B], key: A): int =
  rawGetImpl()

proc `[]`*[A, B](t: TOrderedTable[A, B], key: A): B =
  ## retrieves the value at ``t[key]``. If `key` is not in `t`,
  ## default empty value for the type `B` is returned
  ## and no exception is raised. One can check with ``hasKey`` whether the key
  ## exists.
  var index = rawGet(t, key)
  if index >= 0: result = t.data[index].val

proc mget*[A, B](t: var TOrderedTable[A, B], key: A): var B =
  ## retrieves the value at ``t[key]``. The value can be modified.
  ## If `key` is not in `t`, the ``EInvalidKey`` exception is raised.
  var index = rawGet(t, key)
  if index >= 0: result = t.data[index].val
  else: raise newException(EInvalidKey, "key not found: " & $key)

proc hasKey*[A, B](t: TOrderedTable[A, B], key: A): bool =
  ## returns true iff `key` is in the table `t`.
  result = rawGet(t, key) >= 0

proc rawInsert[A, B](t: var TOrderedTable[A, B], 
                     data: var TOrderedKeyValuePairSeq[A, B],
                     key: A, val: B) =
  rawInsertImpl()
  data[h].next = -1
  if t.first < 0: t.first = h
  if t.last >= 0: data[t.last].next = h
  t.last = h

proc enlarge[A, B](t: var TOrderedTable[A, B]) =
  var n: TOrderedKeyValuePairSeq[A, B]
  newSeq(n, len(t.data) * growthFactor)
  var h = t.first
  t.first = -1
  t.last = -1
  while h >= 0:
    var nxt = t.data[h].next
    if t.data[h].slot == seFilled: 
      rawInsert(t, n, t.data[h].key, t.data[h].val)
    h = nxt
  swap(t.data, n)

proc `[]=`*[A, B](t: var TOrderedTable[A, B], key: A, val: B) =
  ## puts a (key, value)-pair into `t`.
  putImpl()

proc add*[A, B](t: var TOrderedTable[A, B], key: A, val: B) =
  ## puts a new (key, value)-pair into `t` even if ``t[key]`` already exists.
  addImpl()

proc initOrderedTable*[A, B](initialSize=64): TOrderedTable[A, B] =
  ## creates a new ordered hash table that is empty.
  ##
  ## `initialSize` needs to be a power of two. If you need to accept runtime
  ## values for this you could use the ``nextPowerOfTwo`` proc from the
  ## `math <math.html>`_ module.
  assert isPowerOfTwo(initialSize)
  result.counter = 0
  result.first = -1
  result.last = -1
  newSeq(result.data, initialSize)

proc toOrderedTable*[A, B](pairs: openArray[tuple[key: A, 
                           val: B]]): TOrderedTable[A, B] =
  ## creates a new ordered hash table that contains the given `pairs`.
  result = initOrderedTable[A, B](nextPowerOfTwo(pairs.len+10))
  for key, val in items(pairs): result[key] = val

proc `$`*[A, B](t: TOrderedTable[A, B]): string =
  ## The `$` operator for ordered hash tables.
  dollarImpl()

proc sort*[A, B](t: var TOrderedTable[A, B], 
                 cmp: proc (x,y: tuple[key: A, val: B]): int) =
  ## sorts `t` according to `cmp`. This modifies the internal list
  ## that kept the insertion order, so insertion order is lost after this
  ## call but key lookup and insertions remain possible after `sort` (in
  ## contrast to the `sort` for count tables).
  var list = t.first
  var
    p, q, e, tail, oldhead: int
    nmerges, psize, qsize, i: int
  if t.counter == 0: return
  var insize = 1
  while true:
    p = list; oldhead = list
    list = -1; tail = -1; nmerges = 0
    while p >= 0:
      inc(nmerges)
      q = p
      psize = 0
      i = 0
      while i < insize:
        inc(psize)
        q = t.data[q].next
        if q < 0: break 
        inc(i)
      qsize = insize
      while psize > 0 or (qsize > 0 and q >= 0):
        if psize == 0:
          e = q; q = t.data[q].next; dec(qsize)
        elif qsize == 0 or q < 0:
          e = p; p = t.data[p].next; dec(psize)
        elif cmp((t.data[p].key, t.data[p].val), 
                 (t.data[q].key, t.data[q].val)) <= 0:
          e = p; p = t.data[p].next; dec(psize)
        else:
          e = q; q = t.data[q].next; dec(qsize)
        if tail >= 0: t.data[tail].next = e
        else: list = e
        tail = e
      p = q
    t.data[tail].next = -1
    if nmerges <= 1: break
    insize = insize * 2
  t.first = list
  t.last = tail

proc len*[A, B](t: POrderedTable[A, B]): int {.inline.} =
  ## returns the number of keys in `t`.
  result = t.counter

template forAllOrderedPairs(yieldStmt: stmt) {.dirty, immediate.} =
  var h = t.first
  while h >= 0:
    var nxt = t.data[h].next
    if t.data[h].slot == seFilled: yieldStmt
    h = nxt

iterator pairs*[A, B](t: POrderedTable[A, B]): tuple[key: A, val: B] =
  ## iterates over any (key, value) pair in the table `t` in insertion
  ## order.
  forAllOrderedPairs:
    yield (t.data[h].key, t.data[h].val)

iterator mpairs*[A, B](t: POrderedTable[A, B]): tuple[key: A, val: var B] =
  ## iterates over any (key, value) pair in the table `t` in insertion
  ## order. The values can be modified.
  forAllOrderedPairs:
    yield (t.data[h].key, t.data[h].val)

iterator keys*[A, B](t: POrderedTable[A, B]): A =
  ## iterates over any key in the table `t` in insertion order.
  forAllOrderedPairs:
    yield t.data[h].key

iterator values*[A, B](t: POrderedTable[A, B]): B =
  ## iterates over any value in the table `t` in insertion order.
  forAllOrderedPairs:
    yield t.data[h].val

iterator mvalues*[A, B](t: POrderedTable[A, B]): var B =
  ## iterates over any value in the table `t` in insertion order. The values
  ## can be modified.
  forAllOrderedPairs:
    yield t.data[h].val

proc `[]`*[A, B](t: POrderedTable[A, B], key: A): B =
  ## retrieves the value at ``t[key]``. If `key` is not in `t`,
  ## default empty value for the type `B` is returned
  ## and no exception is raised. One can check with ``hasKey`` whether the key
  ## exists.
  result = t[][key]

proc mget*[A, B](t: POrderedTable[A, B], key: A): var B =
  ## retrieves the value at ``t[key]``. The value can be modified.
  ## If `key` is not in `t`, the ``EInvalidKey`` exception is raised.
  result = t[].mget(key)

proc hasKey*[A, B](t: POrderedTable[A, B], key: A): bool =
  ## returns true iff `key` is in the table `t`.
  result = t[].hasKey(key)

proc `[]=`*[A, B](t: POrderedTable[A, B], key: A, val: B) =
  ## puts a (key, value)-pair into `t`.
  t[][key] = val

proc add*[A, B](t: POrderedTable[A, B], key: A, val: B) =
  ## puts a new (key, value)-pair into `t` even if ``t[key]`` already exists.
  t[].add(key, val)

proc newOrderedTable*[A, B](initialSize=64): POrderedTable[A, B] =
  ## creates a new ordered hash table that is empty.
  ##
  ## `initialSize` needs to be a power of two. If you need to accept runtime
  ## values for this you could use the ``nextPowerOfTwo`` proc from the
  ## `math <math.html>`_ module.
  new(result)
  result[] = initOrderedTable[A, B]()

proc newOrderedTable*[A, B](pairs: openArray[tuple[key: A, 
                           val: B]]): POrderedTable[A, B] =
  ## creates a new ordered hash table that contains the given `pairs`.
  result = newOrderedTable[A, B](nextPowerOfTwo(pairs.len+10))
  for key, val in items(pairs): result[key] = val

proc `$`*[A, B](t: POrderedTable[A, B]): string =
  ## The `$` operator for ordered hash tables.
  dollarImpl()

proc sort*[A, B](t: POrderedTable[A, B], 
                 cmp: proc (x,y: tuple[key: A, val: B]): int) =
  ## sorts `t` according to `cmp`. This modifies the internal list
  ## that kept the insertion order, so insertion order is lost after this
  ## call but key lookup and insertions remain possible after `sort` (in
  ## contrast to the `sort` for count tables).
  t[].sort(cmp)

# ------------------------------ count tables -------------------------------

type
  TCountTable* {.final, myShallow.}[
      A] = object ## table that counts the number of each key
    data: seq[tuple[key: A, val: int]]
    counter: int
  PCountTable*[A] = ref TCountTable[A]

proc len*[A](t: TCountTable[A]): int =
  ## returns the number of keys in `t`.
  result = t.counter

iterator pairs*[A](t: TCountTable[A]): tuple[key: A, val: int] =
  ## iterates over any (key, value) pair in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield (t.data[h].key, t.data[h].val)

iterator mpairs*[A](t: var TCountTable[A]): tuple[key: A, val: var int] =
  ## iterates over any (key, value) pair in the table `t`. The values can
  ## be modified.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield (t.data[h].key, t.data[h].val)

iterator keys*[A](t: TCountTable[A]): A =
  ## iterates over any key in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield t.data[h].key

iterator values*[A](t: TCountTable[A]): int =
  ## iterates over any value in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield t.data[h].val

iterator mvalues*[A](t: TCountTable[A]): var int =
  ## iterates over any value in the table `t`. The values can be modified.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield t.data[h].val

proc rawGet[A](t: TCountTable[A], key: A): int =
  var h: THash = hash(key) and high(t.data) # start with real hash value
  while t.data[h].val != 0:
    if t.data[h].key == key: return h
    h = nextTry(h, high(t.data))
  result = -1

proc `[]`*[A](t: TCountTable[A], key: A): int =
  ## retrieves the value at ``t[key]``. If `key` is not in `t`,
  ## 0 is returned. One can check with ``hasKey`` whether the key
  ## exists.
  var index = rawGet(t, key)
  if index >= 0: result = t.data[index].val

proc mget*[A](t: var TCountTable[A], key: A): var int =
  ## retrieves the value at ``t[key]``. The value can be modified.
  ## If `key` is not in `t`, the ``EInvalidKey`` exception is raised.
  var index = rawGet(t, key)
  if index >= 0: result = t.data[index].val
  else: raise newException(EInvalidKey, "key not found: " & $key)

proc hasKey*[A](t: TCountTable[A], key: A): bool =
  ## returns true iff `key` is in the table `t`.
  result = rawGet(t, key) >= 0

proc rawInsert[A](t: TCountTable[A], data: var seq[tuple[key: A, val: int]],
                  key: A, val: int) =
  var h: THash = hash(key) and high(data)
  while data[h].val != 0: h = nextTry(h, high(data))
  data[h].key = key
  data[h].val = val

proc enlarge[A](t: var TCountTable[A]) =
  var n: seq[tuple[key: A, val: int]]
  newSeq(n, len(t.data) * growthFactor)
  for i in countup(0, high(t.data)):
    if t.data[i].val != 0: rawInsert(t, n, t.data[i].key, t.data[i].val)
  swap(t.data, n)

proc `[]=`*[A](t: var TCountTable[A], key: A, val: int) =
  ## puts a (key, value)-pair into `t`. `val` has to be positive.
  assert val > 0
  putImpl()

proc initCountTable*[A](initialSize=64): TCountTable[A] =
  ## creates a new count table that is empty.
  ##
  ## `initialSize` needs to be a power of two. If you need to accept runtime
  ## values for this you could use the ``nextPowerOfTwo`` proc from the
  ## `math <math.html>`_ module.
  assert isPowerOfTwo(initialSize)
  result.counter = 0
  newSeq(result.data, initialSize)

proc toCountTable*[A](keys: openArray[A]): TCountTable[A] =
  ## creates a new count table with every key in `keys` having a count of 1.
  result = initCountTable[A](nextPowerOfTwo(keys.len+10))
  for key in items(keys): result[key] = 1

proc `$`*[A](t: TCountTable[A]): string =
  ## The `$` operator for count tables.
  dollarImpl()

proc inc*[A](t: var TCountTable[A], key: A, val = 1) = 
  ## increments `t[key]` by `val`.
  var index = rawGet(t, key)
  if index >= 0:
    inc(t.data[index].val, val)
  else:
    if mustRehash(len(t.data), t.counter): enlarge(t)
    rawInsert(t, t.data, key, val)
    inc(t.counter)

proc smallest*[A](t: TCountTable[A]): tuple[key: A, val: int] =
  ## returns the largest (key,val)-pair. Efficiency: O(n)
  assert t.len > 0
  var minIdx = 0
  for h in 1..high(t.data):
    if t.data[h].val > 0 and t.data[minIdx].val > t.data[h].val: minIdx = h
  result.key = t.data[minIdx].key
  result.val = t.data[minIdx].val

proc largest*[A](t: TCountTable[A]): tuple[key: A, val: int] =
  ## returns the (key,val)-pair with the largest `val`. Efficiency: O(n)
  assert t.len > 0
  var maxIdx = 0
  for h in 1..high(t.data):
    if t.data[maxIdx].val < t.data[h].val: maxIdx = h
  result.key = t.data[maxIdx].key
  result.val = t.data[maxIdx].val

proc sort*[A](t: var TCountTable[A]) =
  ## sorts the count table so that the entry with the highest counter comes
  ## first. This is destructive! You must not modify `t` afterwards!
  ## You can use the iterators `pairs`,  `keys`, and `values` to iterate over
  ## `t` in the sorted order.

  # we use shellsort here; fast enough and simple
  var h = 1
  while true:
    h = 3 * h + 1
    if h >= high(t.data): break
  while true:
    h = h div 3
    for i in countup(h, high(t.data)):
      var j = i
      while t.data[j-h].val <= t.data[j].val:
        swap(t.data[j], t.data[j-h])
        j = j-h
        if j < h: break
    if h == 1: break

proc len*[A](t: PCountTable[A]): int =
  ## returns the number of keys in `t`.
  result = t.counter

iterator pairs*[A](t: PCountTable[A]): tuple[key: A, val: int] =
  ## iterates over any (key, value) pair in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield (t.data[h].key, t.data[h].val)

iterator mpairs*[A](t: PCountTable[A]): tuple[key: A, val: var int] =
  ## iterates over any (key, value) pair in the table `t`. The values can
  ## be modified.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield (t.data[h].key, t.data[h].val)

iterator keys*[A](t: PCountTable[A]): A =
  ## iterates over any key in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield t.data[h].key

iterator values*[A](t: PCountTable[A]): int =
  ## iterates over any value in the table `t`.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield t.data[h].val

iterator mvalues*[A](t: PCountTable[A]): var int =
  ## iterates over any value in the table `t`. The values can be modified.
  for h in 0..high(t.data):
    if t.data[h].val != 0: yield t.data[h].val

proc `[]`*[A](t: PCountTable[A], key: A): int =
  ## retrieves the value at ``t[key]``. If `key` is not in `t`,
  ## 0 is returned. One can check with ``hasKey`` whether the key
  ## exists.
  result = t[][key]

proc mget*[A](t: PCountTable[A], key: A): var int =
  ## retrieves the value at ``t[key]``. The value can be modified.
  ## If `key` is not in `t`, the ``EInvalidKey`` exception is raised.
  result = t[].mget(key)

proc hasKey*[A](t: PCountTable[A], key: A): bool =
  ## returns true iff `key` is in the table `t`.
  result = t[].hasKey(key)

proc `[]=`*[A](t: PCountTable[A], key: A, val: int) =
  ## puts a (key, value)-pair into `t`. `val` has to be positive.
  assert val > 0
  t[][key] = val

proc newCountTable*[A](initialSize=64): PCountTable[A] =
  ## creates a new count table that is empty.
  ##
  ## `initialSize` needs to be a power of two. If you need to accept runtime
  ## values for this you could use the ``nextPowerOfTwo`` proc from the
  ## `math <math.html>`_ module.
  new(result)
  result[] = initCountTable[A](initialSize)

proc newCountTable*[A](keys: openArray[A]): PCountTable[A] =
  ## creates a new count table with every key in `keys` having a count of 1.
  result = newCountTable[A](nextPowerOfTwo(keys.len+10))
  for key in items(keys): result[key] = 1

proc `$`*[A](t: PCountTable[A]): string =
  ## The `$` operator for count tables.
  dollarImpl()

proc inc*[A](t: PCountTable[A], key: A, val = 1) = 
  ## increments `t[key]` by `val`.
  t[].inc(key, val)

proc smallest*[A](t: PCountTable[A]): tuple[key: A, val: int] =
  ## returns the largest (key,val)-pair. Efficiency: O(n)
  t[].smallest

proc largest*[A](t: PCountTable[A]): tuple[key: A, val: int] =
  ## returns the (key,val)-pair with the largest `val`. Efficiency: O(n)
  t[].largest

proc sort*[A](t: PCountTable[A]) =
  ## sorts the count table so that the entry with the highest counter comes
  ## first. This is destructive! You must not modify `t` afterwards!
  ## You can use the iterators `pairs`,  `keys`, and `values` to iterate over
  ## `t` in the sorted order.
  t[].sort

when isMainModule:
  type
    Person = object
      firstName, lastName: string

  proc hash(x: Person): THash =
    ## Piggyback on the already available string hash proc.
    ##
    ## Without this proc nothing works!
    result = x.firstName.hash !& x.lastName.hash
    result = !$result

  var
    salaries = initTable[Person, int]()
    p1, p2: Person
  p1.firstName = "Jon"
  p1.lastName = "Ross"
  salaries[p1] = 30_000
  p2.firstName = "소진"
  p2.lastName = "박"
  salaries[p2] = 45_000
  var
    s2 = initOrderedTable[Person, int]()
    s3 = initCountTable[Person]()
  s2[p1] = 30_000
  s2[p2] = 45_000
  s3[p1] = 30_000
  s3[p2] = 45_000
