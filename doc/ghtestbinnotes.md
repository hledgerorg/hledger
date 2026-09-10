Here you can find unreleased test binaries, which are updated occasionally. By using these and providing [feedback](https://hledger.org/support.html), you can help to make the next release better.

These binaries have the following changes since the 1.52.4 release: https://github.com/hledgerorg/hledger/compare/1.52.4...testlatest

<details>
<summary>

## Install

</summary>

<xdetails>
<summary>

### All platforms

</summary>

If you have [eget](https://github.com/zyedidia/eget), that's a convenient way to download the right binaries for your machine:
```
eget simonmichael/hledger --pre-release --all
```
Otherwise:

</xdetails>
<xdetails>
<summary>

### GNU/Linux, 64-bit Intel

</summary>

At the command line:

```
cd /usr/local/bin
curl -fLOC- https://github.com/hledgerorg/hledger/releases/download/testbin/hledger-linux-x64.tar.gz
tar xzf hledger-linux-x64.tar.gz
cd
hledger --version; hledger-ui --version; hledger-web --version    # should show a recent .99 version
```

</xdetails>
<xdetails>
<summary>

### Mac, 64-bit ARM or Intel

</summary>

In a terminal window (don't use your web browser to download, it won't authorise the binaries):
<!--
(Hopefully these commands are all installed by default; 
if not, install [XCode Command Line Tools](https://mac.install.guide/commandlinetools/) 
and/or [Homebrew](https://brew.sh), and let me know.)
-->

For ARM macs:
  ```
  cd /usr/local/bin
  curl -fLOC- https://github.com/hledgerorg/hledger/releases/download/testbin/hledger-mac-arm64.tar.gz
  tar xzf hledger-mac-arm64.tar.gz
  cd
  hledger --version; hledger-ui --version; hledger-web --version    # should show a .99 version with the testbin release's date
  ```

For Intel macs:
  ```
  cd /usr/local/bin
  curl -fLOC- https://github.com/hledgerorg/hledger/releases/download/testbin/hledger-mac-x64.tar.gz
  tar xzf hledger-mac-x64.tar.gz
  cd
  hledger --version; hledger-ui --version; hledger-web --version    # should show a .99 version with the testbin release's date
  ```

</xdetails>
<xdetails>
<summary>

### Windows, 64-bit ARM or Intel

</summary>

In a powershell window (press `WINDOWS-R`, `powershell`, `ENTER`):

1. Make a place to keep installed binaries. You only need to do this once, not for every release:
    ```
    mkdir -force $HOME\bin >$null
    $ENV:PATH += ";"+$HOME+"\bin"
    [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)+";"+$HOME+"\bin", [EnvironmentVariableTarget]::User)
    ```

2. Download and install the release binaries:
    ```
    cd $HOME\bin
    curl https://github.com/hledgerorg/hledger/releases/download/testbin/hledger-windows-x64.zip -OutFile hledger-windows-x64.zip
    Expand-Archive hledger-windows-x64.zip -DestinationPath . -Force
    cd $HOME
    hledger --version; hledger-ui --version; hledger-web --version    # should show a .99 version with the testbin release's date; if not: where.exe hledger
    ```

3. Ensure a default journal file exists, and without a problematic encoding (I'm not sure if/why "ascii" was needed here).
This will allow you to start hledger-web by double-clicking on its icon if you wish.
    ```
    out-file -append -encoding ascii $HOME/.hledger.journal
    ```

</xdetails>
<xdetails>

</details>
