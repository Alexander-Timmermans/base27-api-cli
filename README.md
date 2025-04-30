Base27 API CLI (CUBA Platform / Jmix naming convention)

This is a third party CLI tool, based on the [online documentation](https://community.base27.eu/doc/rest/).

```
Usage: ./base27_api.sh [options]
  Options:                                           Description:                        Output-type:
  -c                                                 Generate / validate config          
  -u                                                 Use form encoding                   

  --list-endpoints                                   List all API endpoints              text
  --list-metadata-entities                           List all metadata/entities          text
  --list-metadata-enums                              List all metadata/enums             text
  --list-metadata-datatypes                          List all metadata/datatypes         text
  --list-messages-entities                           List all messages/entities          text
  --list-messages-enums                              List all messages/enums             text
  --list-services                                    List all services                   text

  -je | --json-entity   '<name>'                     Derive JSON template for entity     JSON
  -jn | --json-enum     '<name>'                     Derive JSON template for enum       JSON
  -jd | --json-datatype '<name>'                     Derive JSON template for datatype   JSON

  -e | --entity         '<name>'                     Inspect an entity name              JSON
  -s | --service        '<name>'                     Inspect a service name              JSON
  -f | --file           '<id>'                       Inspect a file id                   JSON

  -g | --get            <endpoint> [key=value ...]   GET an endpoint                     JSON
  -p | --post           <endpoint> [key=value ...]   POST to an endpoint                 JSON
  -t | --put            <endpoint> [key=value ...]   PUT to an endpoint                  JSON
  -d | --delete         <endpoint> [key=value ...]   DELETE to an endpoint               JSON
```

e.g.:

```
./base27_api.sh --list-metadata-entities | grep -i datasubjectrequest
base$DataSubjectRequestType
base$DataSubjectRequest
base$DataSubjectRequestStatus

./base27_api.sh -e 'base$DataSubjectRequest'
GET entities/base$DataSubjectRequest:
[
  {
    "_entityName": "base$DataSubjectRequest",
    "_instanceName": "1 - ",
    "id": "<uuid>",
    "version": 1,
    "changed": false,
    "nr": 1,
    "applyWorkflow": true,
    "status": "New"
  }
]

./base27_api.sh -g metadata/entities id=123 | head
GET metadata/entities, id=123:
[
  {
    "entityName": "base$Likelihood",
    "ancestor": "base$RiskModelAttribute",
    "properties": [
      {
```

