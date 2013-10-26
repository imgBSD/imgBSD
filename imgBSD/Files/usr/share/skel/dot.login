# $FreeBSD: src/share/skel/dot.login,v 1.17.4.1 2011/09/23 00:51:37 kensmith Exp $
#
# .login - csh login script, read by login shell, after `.cshrc' at login.
#
# see also csh(1), environ(7).
#

if ( -x /usr/games/fortune ) /usr/games/fortune freebsd-tips
