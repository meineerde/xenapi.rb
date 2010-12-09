# XenAPI.rb

* Author: Holger Just
* URL: http://dev.holgerjust.de/projects/xenapi-rb

This is a translation of XenAPI.py into Ruby. This script can be used to talk
to the XMLRPC API of a Citrix XenServer.

This library is in no way endorsed or supported by Citrix or XenSource and is
provided as is. It is probably useful, but might also neuter your dog, sleep
with your wife, and sell your house on eBay. So don't blame me.

* API Documentation: http://docs.vmd.citrix.com/XenServer/5.6.0/1.0/en_gb/api/
* Other SDK variants: http://community.citrix.com/display/xs/Download+SDKs

# Restrictions

* As the rpcxml library as well as net/http of ruby do not support unix domain
  sockets by default, this library supports only the HTTP transport currently.

# Examples

    require 'xenapi'
    
    # first create a connection and login
    session = XenAPI::Session.new("https://xen-server.example.com")
    begin
      session.login_with_password("root", "supersecret")
      
      # Now we can use the whole API directly via the session object.
      # In this example, we just list all available VMs on the server
      vms = session.VM.get_all
      vms.each do |vm|
        record = session.VM.get_record(vm)
        unless record['is_a_template'] || record['is_control_domain']
          name = record['name_label']
          puts "Found VM uuid #{record['uuid']} called #{name}"
        end
      end
    ensure
      # make sure we clean up after us
      session.logout
    end

# License

This library is based on
[XenAPI.py](http://community.citrix.com/download/attachments/38633496/XenAPI.py?version=1)
by XenSource Inc., licensed under the
[GNU Lesser General Public License](http://www.gnu.org/licenses/lgpl.html).

Copyright (c) 2010 Holger Just

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.