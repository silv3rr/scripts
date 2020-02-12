# Rescan

## Example oneliners

**rescan all dirs in '/site/foo':**

`GLROOT=/glftpd; for i in $GLROOT/site/foo/*; do chroot $GLROOT /bin/rescan --normal --dir="$(echo $i|sed s@$GLROOT@@)"; done`

**as multiple line script:**

```bash
#!/bin/sh
GLROOT=/glftpd
for i in $GLROOT/site/foo/*; do
  chroot $GLROOT /bin/rescan --normal --dir="$(echo $i | sed s@$GLROOT@@)"
done
```

**for all dirs in both 'foo' and 'bar' use this glob instead:**

`$GLROOT/site/{foo,bar}/*`

**to "parallelize" change the end of the example line :)**

replace `'; done'` with `'& done' `

**recursive, replace 'for' in the example line with:** 

`for i in $(find $GLROOT/site -mindepth 1 -maxdepth 2 -type d); do <...>`

**...and of course there's daxxars total-rescan:**

<https://github.com/pzs-ng/scripts/blob/master/total-rescan/total-rescan.pl>
