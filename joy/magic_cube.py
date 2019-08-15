

"""

    a4
a1   |a3
| a2 | |
|  |b2 |
b3 |  b1
  b4


1/2 : 1423<->1324

1/4 : 1243<->1342

1/3 : 1234<->1432

"""

dump_format = """
    3
  /   \\
4   |   2
  y   x
|   0   |
  /   \\
5   z   1
  \   /
    6
"""

state = [0,1,2,3,4,5,6]

def dump_state():
    first = ["a", "b", "c", "d", "e", "f", "g"]
    re = dump_format
    for i in range(7):
        re = re.replace(str(i), first[i])
    for i in range(7):
        re = re.replace(first[i], str(state[i]))
    print(re)

def reset():
    for i in range(7):
        state[i] = i
    dump_state()

def _x():
    state[1], state[2], state[3], state[0] = state[0], state[1], state[2], state[3]

def x():
    _x()
    dump_state()

def rx():
    _x()
    _x()
    _x()
    dump_state()

def _y():
    state[3], state[4], state[5], state[0] = state[0], state[3], state[4], state[5]

def y():
    _y()
    dump_state()

def ry():
    _y()
    _y()
    _y()
    dump_state()

def _z():
    state[5], state[6], state[1], state[0] = state[0], state[5], state[6], state[1]

def z():
    _z()
    dump_state()

def rz():
    _z()
    _z()
    _z()
    dump_state()



if __name__=="__main__":
    x()
    y()
    z()
    reset()
