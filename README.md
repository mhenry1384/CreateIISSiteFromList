Used to create Windows IIS sites with bindings and certificates.  I use this to create sites during Octopus Deploy deployments.  It is more convenient for creating sites with many different bindings than the steps available in the Octopus step template library.  See CreateIISSiteFromListTest.lst for an example.

If you have a number of bindings and environments, specifying bindings using the "IIS web site and application pool" feature quickly gets complicated.  This module allows us to specify all the bindings and certificates in a clean and simple manner.

Note - does not currently support SNI, only the normal certificate bindings where you have one cert per IP address.