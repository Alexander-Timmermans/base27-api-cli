Base27 API CLI (CUBA Platform / Jmix naming convention)

This is a third party CLI tool, based on the [online documentation](https://community.base27.eu/doc/rest/).

```
Usage: ./base27_api.sh [options]
  Options:                                           Description:                          Output-type:
  -c                                                 Generate / validate config            
  -u                                                 Use form encoding                     

  --list-endpoints                                   List all API endpoints                text
  --list-metadata-entities                           List all metadata/entities            text
  --list-metadata-enums                              List all metadata/enums               text
  --list-metadata-datatypes                          List all metadata/datatypes           text
  --list-messages-entities                           List all messages/entities            text
  --list-messages-enums                              List all messages/enums               text
  --list-services                                    List all services                     text

  -me | --get-entity     '<name>'                    GET metadata of an entity             JSON
  -mn | --get-enum       '<name>'                    GET metadata of an enum               JSON

  -jm | --json-mandatory '<name>'                    Generate a mandatory entity template  JSON
  -jw | --json-writeable '<name>'                    Generate a writable entity template   JSON
  -jf | --json-full      '<name>'                    Generate a full entity template       JSON

  -e | --entity          '<name>'                    Inspect an entity name                JSON
  -s | --service         '<name>'                    Inspect a service name                JSON
  -f | --file            '<id>'                      Inspect a file id                     JSON

  -g | --get             <endpoint>                  GET an endpoint                       JSON
  -p | --post            <endpoint> [key=value ...]  POST to an endpoint                   JSON
  -t | --put             <endpoint> [key=value ...]  PUT to an endpoint                    JSON
  -d | --delete          <endpoint>                  DELETE an endpoint                    JSON
```

e.g.:

```
./base27_api.sh --list-metadata-entities | grep -i datasubjectrequest
base$DataSubjectRequestType
base$DataSubjectRequest
base$DataSubjectRequestStatus

./base27_api.sh -e 'base$DataSubjectRequest'
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

./base27_api.sh -g entities/'base$DataSubjectRequest'/<uuid>
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

```

