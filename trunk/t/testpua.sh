# only for testserver! don't use, it kills old sessions
killall -q pua.pl
killall -q pua.pl
sleep 1
echo pua.pl $*
cd ..
pua.pl -d 0  -x localhost  $* &
