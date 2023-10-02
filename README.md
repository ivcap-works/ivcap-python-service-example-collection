# IVCAP Demo Service

This directory implements a simple IVCAP service which creates a thumbnail image as
well as some stats for every image in a collection referred to by the images' parameter.

## Usage: User Perspective

We assume that the service has already been deployed. To check that, we can use the `ivcap` cli tool.

```
% ivcap service list
+----+--------------------------+------------------------------------+
| ID | NAME                     | PROVIDER                           |
+----+--------------------------+------------------------------------+
| @1 | image-analysis-example   | urn:ivcap:provider:45a06508-...    |
....
```

To get more information on the service itself:

```
% ivcap service get @1

          ID  urn:ivcap:service:19f9c31e-...                                   
        Name  image-analysis-example                                                                    
 Description  A simple IVCAP service creating a thumbnail and reporting stats on a collection of images 
      Status  ???                                                                                      
 Provider ID  urn:ivcap:provider:45a06508-...                                 
  Account ID  urn:ivcap:account:45a06508-...                                   
  Parameters  ┌────────┬────────────────────────────────┬────────────┬─────────┐                        
              │ NAME   │ DESCRIPTION                    │ TYPE       │ DEFAULT │                        
              ├────────┼────────────────────────────────┼────────────┼─────────┤                        
              │ images │ Collection of image artifacts. │ collection │ ???     │                        
              ├────────┼────────────────────────────────┼────────────┼─────────┤                        
              │  width │ Thumbnail width.               │ int        │ 100     │                        
              ├────────┼────────────────────────────────┼────────────┼─────────┤                        
              │ height │ Thumbnail height.              │ int        │ 100     │                        
              └────────┴────────────────────────────────┴────────────┴─────────┘                        
```

We can now _order_ a run over a collection by creating an _order_:

```
% ivcap order create -n "test run #1" urn:ivcap:service:19f9c31e-... images=urn:ibenthos:collection:43fa8191...
Order 'urn:ivcap:order:503e98af-...' with status 'pending' submitted.
```

To check progress on this order:

```
% ivcap order get urn:ivcap:order:77b3780b-2b8b-41f3-b4d3-e62fac4248b2

         ID  urn:ivcap:order:77b3780b-2b8b-41f3-b4d3-e62fac4248b2                                                          
       Name  urn:ibenthos:collection:indo_flores_0922:LB4 UQ PhotoTransect@671984                                          
     Status  executing                                                                                                     
    Ordered  1 minute ago (02 Oct 23 15:17 AEDT)                                                                           
    Service  image-analysis-example (@10)                                                                                  
 Account ID  urn:ivcap:account:45a06508-5c3a-4678-8e6d-e6399bf27538
 Parameters  ┌─────────────────────────────────────────────────────────────────────┐
             │ images =  @1 (urn:ivcap:queue:ea11d34d-636b-49da-be12-e361acd511aa) │
             │  width =  100                                                       │
             │ height =  100                                                       │
             └─────────────────────────────────────────────────────────────────────┘
```

Which should finally change to something like:

```
% ivcap order get urn:ivcap:order:77b3780b-2b8b-41f3-b4d3-e62fac4248b2

         ID  urn:ivcap:order:77b3780b-2b8b-41f3-b4d3-e62fac4248b2
       Name  urn:ibenthos:collection:indo_flores_0922:LB4 UQ PhotoTransect@671984                                          
     Status  succeeded                                                                                                     
    Ordered  1 minute ago (02 Oct 23 15:17 AEDT)                                                                           
    Service  image-analysis-example (@10)                                                                                  
 Account ID  urn:ivcap:account:45a06508-5c3a-4678-8e6d-e6399bf27538
 Parameters  ┌─────────────────────────────────────────────────────────────────────┐
             │ images =  @1 (urn:ivcap:queue:ea11d34d-636b-49da-be12-e361acd511aa) │
             │  width =  100                                                       │
             │ height =  100                                                       │
             └─────────────────────────────────────────────────────────────────────┘
   Products  ┌────┬─────────────────────────────────┬──────────────────┐
             │ @2 | urn:ivcap:artifact:659cefac-... │ application/json │
             │ @3 │ urn:ivcap:artifact:e5340ba9-... │ image/png        │
             └────┴─────────────────────────────────┴──────────────────┘
   Metadata  ┌────┬────────────────────────────────────────────┐
             │ @4 │ urn:ivcap:schema:order-finished.1          │
             │ @5 │ urn:ivcap:schema:order-placed.1            │
             │ @6 │ urn:ivcap:schema:order-produced-artifact.1 │
             │ @7 │ urn:ivcap:schema:order-produced-artifact.1 │
             │ @8 │ urn:ivcap:schema:order-uses-artifact.1     │
             │ @9 │ urn:ivcap:schema:order-uses-workflow.1     │
             └────┴────────────────────────────────────────────┘
```

The service produces multiple images, one for each in the input collection. Let's check out the image:

```
% ivcap artifact get @3

         ID  urn:ivcap:artifact:e5340ba9-...                         
       Name  urn:ivcap:artifact:e5340ba9-...
     Status  ready                                                                            
       Size  16 kB                                                                            
  Mime-type  image/png
 Account ID  urn:ivcap:account:45a06508-5c3a-4678-8e6d-e6399bf27538
   Metadata  ┌────┬─────────────────────────────────────────────┐
             │ @1 │ urn:example:schema:image-analysis:thumbnail │
             │ @2 │ urn:ivcap:schema:artifact-usedBy-order.1    │
             │ @3 │ urn:ivcap:schema:artifact.1                 │
             └────┴─────────────────────────────────────────────┘
```

To download the image, use the artifact ID from the above _image.png_
(`ID  urn:ivcap:artifact:e5340ba9-...`):

```
% ivcap artifact download urn:ivcap:artifact:e5340ba9-... -f /tmp/image.jpg
... downloading file 100% [==============================] (750 kB/s)
```

## Build & Deployment

First, we need to setup a Python environment:

```
conda create --name ivcap_service python=3.8 -y
conda activate ivcap_service
pip install -r requirements.txt
```

To check if everything is properly installed, use the `run` target to execute the
service locally:

```
% make run
mkdir -p .../DATA/run && rm -rf .../DATA/run/*
python img_analysis_service.py \
                --images ./examples \
                --ivcap:out-dir ./DATA/run
INFO 2023-10-02T15:49:39+1100 ivcap IVCAP Service 'image-analysis-example' ?/? (sdk 0.4.0) built on ?.
INFO 2023-10-02T15:49:39+1100 ivcap Starting order 'urn:ivcap:order:00000000-0000-0000-0000-000000000000' for service 'image-analysis-example' on node 'None'
INFO 2023-10-02T15:49:39+1100 ivcap Starting service with 'ServiceArgs(images=<LocalCollection path=.../examples>, width=100, height=100)'
INFO 2023-10-02T15:49:39+1100 service mime-type: image/jpeg
INFO 2023-10-02T15:49:39+1100 service processing 'Clown_fish_in_the_Andaman_Coral_Reef.wikimedia.jpg'
INFO 2023-10-02T15:49:39+1100 ivcap Written artifact 'Clown_fish_in_the_Andaman_Coral_Reef.wikimedia.png' to '.../DATA/run/Clown_fish_in_the_Andaman_Coral_Reef.wikimedia.png'
INFO 2023-10-02T15:49:39+1100 service mime-type: image/jpeg
INFO 2023-10-02T15:49:39+1100 service processing 'Closed_Brain_Coral.wikimedia.jpg'
INFO 2023-10-02T15:49:39+1100 ivcap Written artifact 'Closed_Brain_Coral.wikimedia.png' to '.../DATA/run/Closed_Brain_Coral.wikimedia.png'
INFO 2023-10-02T15:49:39+1100 service mime-type: image/jpeg
INFO 2023-10-02T15:49:39+1100 service processing 'Black_coral.wikimedia.jpg'
INFO 2023-10-02T15:49:39+1100 ivcap Written artifact 'Black_coral.wikimedia.png' to '.../DATA/run/Black_coral.wikimedia.png'
>>> Output should be in './DATA'
```

To build the docker container, publish it to the repository and register the service with the respective
IVCAP deploymewnt.

```
make docker-publish
```

Submit the service description to an IVCAP cluster. This assumes that the `ivcap-cli` tool is installed and the user is properly logged into the respective service account.

```
make service-register
```

Please note the service ID (e.g. `urn:ivcap:service:...`) as we will need that when ordering this service.

## Development

This service is implemented in `image_analysis_service.py` and consists of the following parts:

1. Service description
1. Service entry point
1. I/O
1. Service registration

### Service Description

The IVCAP SDK provides some convenience functions to describe the service and its parameters:

```python
from ivcap_sdk_service import Service, Parameter, Option, Type, ServiceArgs

SERVICE = Service(
    name = "image-analysis-example",
    description = "A simple IVCAP service creating a thumbnail and reporting stats on a collection of images",
    parameters = [
        Parameter(
            name='images', 
            type=Type.COLLECTION, 
            description='Collection of image artifacts.',
            optional=True),
    ...
```

### Service Entrypoint

This function is called with a `Dict` containing all the service parameter settings according to the
above `SERVICE` declaration.

```python
def service(args: ServiceArgs, svc_logger: logging):
    """Called after the service has started and all paramters have been parsed and validated

    Args:
        args (ServiceArgs): A Dict where the key is one of the `Parameter` defined in the above `SERVICE`
        svc_logger (logging): Logger to use for reporting information on the progress of execution
    """
    ...
```

### I/O

One of the paramters is `images`, which is of type `collection` and will therefore already been
_wrapped_ in an iterator of `IOReadable` instances which is a _file-like_ object and can often be directly provided as argument to functions expecting such an instance:

```python
  ...
  thumb_size = (args.width, args.height)
  for img_a in args.images:
      img_a.seek(0)
      logger.info(f"mime-type: {img_a.mime_type}")
      process_image(img_a, thumb_size)
```

To publish a result (aka _product_), we call the `publish_artifact` function. Before we do that,
it is highly recommended to define _metadata_ further describing the result. the `create_metadata`
function is a convenience function to create a properly formatted metadata object. The first argument
is the schema to be used (`urn:example:schema:...`), followed by an arbitrary list of named values.

The first parameter to the `publish_artifact` function is a name useful for debugging. The second on is
a lambda function called with a writable file descriptor to save the created image into
(`img.save(fd, format="png")`). The third parameter is the above described metadata descriptor.

```python
  meta = create_metadata('urn:example:schema:image-analysis:thumbnail', artifact=img_a.urn)
  publish_artifact(f"{img_name}.png", lambda fd: img.save(fd, format="png"), SupportedMimeTypes.PNG, metadata=meta)
```

A different type of result is a record described by a schema. In this example, we also report some
stats on the various input images via `publish_result`:

```python
def report_stats(img_a: IOReadable):
  with Image.open(img_a) as img:
      img = Image.open(img_a)
      res: MetaDict = {
          "artifact": img_a.urn,
          "mean": stat.mean,
          "median": stat.median,
          "stddev": stat.stddev,
      }
      publish_result(res, 'urn:example:schema:image-analysis:analysis')
```

### Service registration

Finally, we need to register the `SERVICE` description and the `service(...)` entry function with IVCAP
providing the above describe `SERVICE` description as well as the `service` entry function.

```python
register_service(SERVICE, service)
```

### Testing & Troubleshooting

Please refer to the various `run...` targets in the [Makefile](Makefile)
