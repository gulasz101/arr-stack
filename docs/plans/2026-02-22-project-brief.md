# migration to arr-box

Context

currently arr-stack is running exclusively on host you are running on, my macbook

it is less than ideal, as always when my wife wants to watch something i have to have my laptop running in local network, she is watching using jellyfin on android-tv box

your task:
move entire library to my homelab

- [ ] move the files to openmediavault.local
	- [ ] you can login there over ssh by `ssh openmediavault` (host (my macbook) is configured, to not prompt for password)
    - [ ] you must create specific user for arr-box for storing files and accessing files
    - [ ] openmedia vault will be used as peristent storage for multiple devices over my network ,that is why i want multiple user accounts with meaningfull not overlapping access
- [ ] move configuration to arr-box.local (let's continue running it with docker compose)
	- [ ] you can login there using `ssh arr-box` (host is configured, to not prompt for password)
    - [ ] by thefault you are logged in as `gulasz101` user (sudo) in case you need to install something there, there is no docker, nothing… vanilla debian, just ssh and netbird
        - [ ] I'm ok having arr-box specific user, gulasz101 is generic one i'm making quite often
    - [ ] arr-stack on arr-box must alwyas autostart
    - [ ] arr-stack must be available through local network (arr-box.local from my android tv) and over netbird in case i would connect as a peer to the network from my phone (arr-box.netbird.cloud) keep this in mind for sake of changing configuration of dashboard container, so i can access normally from mobile device or local network
    - [ ] when i'm accessing (arr-box.netbird.cloud|arr-box.local) in browser, i want dashboard to be open by default
    
The goal is that the arr-box has all the watching history migrated from my macbook
all movies and series migrated from my macbook.

Once i wil confirm evertything is migrated i will delete stuff manually from my macbook, do not delete anything on my local.

For copying files between macbook and openmediavault use copyparty (you have to install it on both). Copyparty gives the best performance with parralel chunk uploads. This is important as I want this to be included later in my blogpost.

on macbook you have access to authenticated `gh` command, in case there is need to make some changes to repo, repo MUST stay private as i do not want to leak credentials. 

If it is possible to move credentials to github secrets, do it, so i will not have to be scared about leaking them. Instead of using github secrets i'm also ok using `sops` for encoding anything sensitive, but then i have to have some way of storing master key in 1password for instance, so i will be able to decode all the secrets in future.

Ideally if all the transition is "git ops" driven, so all changes are commited to repo, so i can review later what actually happen. Make all the changes incremential with small relevant commits properly described in commit messages and related to specific parts of plan files.

All the plans files, and entire progress has to be documented under docs/plans in markdown files, make it as verbose as possible, so later I can use some other coding agent to make a blog post out of that.

Use brainstorimg / write-plans / subagent-driven-development skills to perform antire operation

