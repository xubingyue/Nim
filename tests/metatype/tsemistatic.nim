discard """
  msg: "static 10\ndynamic\nstatic 20\n"
  output: "s\nd\nd\ns"
  disabled: "true"
"""

proc foo(x: semistatic[int]) =
  when isStatic(x):
    static: echo "static ", x
    echo "s"
  else:
    static: echo "dynamic"
    echo "d"

foo 10

var
  x = 10
  y: int

foo x
foo y

foo 20

