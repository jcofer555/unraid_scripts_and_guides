```bash
#!/bin/bash

        #### DON'T CHANGE ANYTHING BELOW HERE ####
        
docker ps --format "{{.ID}} {{.Names}}" | sort -k2 | awk '{print $1}' | xargs -I {} docker inspect --format '{{.Name}}
Container Port -> Host Port
{{range $k, $v := .NetworkSettings.Ports}}{{if $v}}{{$k}} -> {{(index $v 0).HostPort}}
{{end}}{{end}}' {} | sed 's/^\///'
```
