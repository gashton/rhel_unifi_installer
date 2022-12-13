# rhel_unifi_installer
Ubiquiti Networks - UniFi Controller complete installer and upgrader for RedHat and CentOS 6/7

Note: Due to the unavailabiliy of RPM packages from Ubiquiti, this solution provides an interim solution. Automating installation of the application and services files including support for SELinux enabled systems running in an enforcing mode.

# Download & Install Example

1. `cd /tmp/`

2. `git clone https://github.com/gashton/rhel_unifi_installer.git`

3. `bash /tmp/rhel_unifi_installer/InstallUnifi.sh -f install -v 5.5.20 -d /opt/`

# Usage

<pre>
UniFi CentOS/RedHat installer/upgrader
usage: ./InstallUnifi.sh -f install -v &lt;VERSION&gt; -d &lt;INSTALL_PATH&gt; {-y} {-s} | -f remove
 -f &lt;ACTION&gt;         "install" or "remove"
 -v &lt;VERSION&gt;        (Install) What version to download and install
 -d &lt;INSTALL_PATH&gt;   (Install) Where to install UniFi
 -y                  (Install) Overwrite existing installation (Data will be backed up and restored)
 -s                  (Install) Install as service (WARNING: This will overwrite any existing configuration)
</pre>
