# tools-for-orca.bash

The intention of this repository is to provide some scripts
which should help with the execution and submission of ORCA.

Currently only a submission script is available,
and it is pretty much tailored to the RWTH Cluster (CLAIX18).

To view a short description, issue:
```
orca.submit.sh -h
```

Configuration of the script with the files
`orca.tools.rc` or `.orca.toolsrc` (has precedence) 
in one of the directories:
installation directory, `HOME`, `HOME/.config`, `PWD`.
The last found file will be applied.

## License

GNU General Public License v3.0

See [LICENSE](LICENSE) to see the full text.

