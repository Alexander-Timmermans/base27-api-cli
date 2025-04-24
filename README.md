Base27 API CLI (CUBA Platform / Jmix naming convention)

This is a third party CLI tool, based on the [online documentation](https://community.base27.eu/doc/rest/).

```
Usage: ./base27_api.sh [options]
  Options:                                  Description:                  Output-type:
  -c                                        Generate / validate config    
  -u                                        Use form encoding             

  -g | --get     <endpoint> [key=value ...] GET an endpoint               JSON
  -p | --post    <endpoint> [key=value ...] POST to an endpoint           JSON
  -t | --put     <endpoint> [key=value ...] PUT to an endpoint            JSON
  -d | --delete  <endpoint> [key=value ...] DELETE to an endpoint         JSON

  -e | --entity  '<name>'                   List contents of entity name  JSON
  -s | --service '<name>'                   List contents of service name JSON
  -f | --file    '<id>'                     List contents of file id      JSON

  --list-endpoints                          List all API endpoints        text
  --list-metadata-entities                  List all metadata/entities    text
  --list-metadata-enums                     List all metadata/enums       text
  --list-metadata-datatypes                 List all metadata/datatypes   text
  --list-messages-entities                  List all messages/entities    text
  --list-messages-enums                     List all messages/enums       text
  --list-services                           List all services             text
  --list-userinfo                           List userinfo                 text
```
e.g. `./base27_api.sh --get metadata/entities id=123`

