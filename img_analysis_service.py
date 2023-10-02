from PIL import Image, ImageStat
import logging
import os

from ivcap_sdk_service import Service, Parameter, Type, SupportedMimeTypes, ServiceArgs, IOReadable, MetaDict
from ivcap_sdk_service import register_service, publish_artifact, publish_result, create_metadata

logger = None # set when called by SDK

SERVICE = Service(
    name = "image-analysis-example",
    description = "A simple IVCAP service creating a thumbnail and reporting stats on a collection of images",
    parameters = [
        Parameter(
            name='images', 
            type=Type.COLLECTION, 
            description='Collection of image artifacts.',
            optional=True),
        Parameter(
            name='width', 
            type=Type.INT, 
            description='Thumbnail width.',
            default=100),
        Parameter(
            name='height', 
            type=Type.INT, 
            description='Thumbnail height.',
            default=100),
    ]
)

def service(args: ServiceArgs, svc_logger: logging):
    """Called after the service has started and all paramters have been parsed and validated

    Args:
        args (ServiceArgs): A Dict where the key is one of the `Parameter` defined in the above `SERVICE`
        svc_logger (logging): Logger to use for reporting information on the progress of execution
    """
    global logger 
    logger = svc_logger
    
    thumb_size = (args.width, args.height)
    for img_a in args.images:
        img_a.seek(0)
        logger.info(f"mime-type: {img_a.mime_type}")
        process_image(img_a, thumb_size)
        
def process_image(img_a: IOReadable, thumb_size: tuple):
    logger.info(f"processing '{img_a.name}'")
    create_thumbnail(img_a, thumb_size)
    report_stats(img_a)

def report_stats(img_a: IOReadable):
    with Image.open(img_a) as img:
        img = Image.open(img_a)
        stat = ImageStat.Stat(img, mask=None)
        res: MetaDict = {
            "artifact": img_a.urn,
            "mean": stat.mean,
            "median": stat.median,
            "stddev": stat.stddev,
        }
        publish_result(res, 'urn:example:schema:image-analysis:analysis')
    
def create_thumbnail(img_a: IOReadable, thumb_size: tuple):
    with Image.open(img_a) as img:
        img_name = os.path.splitext(img_a.name)[0]
        img.thumbnail(thumb_size)
        meta = create_metadata('urn:example:schema:image-analysis:thumbnail', artifact=img_a.urn)
        publish_artifact(f"{img_name}.png", lambda fd: img.save(fd, format="png"), SupportedMimeTypes.PNG, metadata=meta)

####
# Entry point
register_service(SERVICE, service)
