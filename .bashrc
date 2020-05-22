source /etc/skel/.bashrc

alias importpath_gcc='cd ~/buildroot-2015.11.1/output/host; source importpath_gcc; cd -'
alias importpath_r16='cd ~/buildroot-2015.11.1/output/host; source importpath_r16; cd -'

importpath_gcc

echo "To import additional environment variables specific to the R16, run importpath_r16"

cd ~
