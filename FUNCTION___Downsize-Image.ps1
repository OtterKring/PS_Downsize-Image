<#
.SYNOPSIS
Downsize an Image to match a given byte-size (uncompressed filesize)

.DESCRIPTION
Take and image, from file or provided as byte array, downsize it to match a given filesize (in bytes) and return it either as file or as byte array.
Resizing will only take place if the original is larger than the target picture.

.PARAMETER InputFile
Absolute path of image file

.PARAMETER OutputFile
Absolue path of output file

.PARAMETER ImageBytes
Array of bytes containing image data

.PARAMETER TargetFileSizeInByte
Desired size of the resulting image in bytes

DEFAULT = 100000

.PARAMETER jpegQuality
Desired quality of jpeg compression

RANGE   = 0 - 100
DEFAULT = 90

.EXAMPLE
# downsize pic.jpg to a maximum filesize of 1mb
Downsize-Image -InputFile 'C:\Images\pic.jpg' -OutputFile 'C:\Images\pic2.jpg' -TargetFileSizeInBytes ([math]::pow(1024,2))

.EXAMPLE
# donwsize the Active Directory thumbnailPhoto of user Einstein and write it back to Active Directory
$ba = (Get-ADUser einstein -Properties thumbnailphoto).thumbnailphoto
$ba = Downsize-Image -ImageBytes $ba
Set-ADUser einstein -Replace @{thumbnailphoto=$ba}

.NOTES
Maximilian Otter, 2020-08-27
#>
function Downsize-Image
{
    Param(
        [string]$InputFile,
        [string]$OutputFile,  # full path required!!!
        [byte[]]$ImageBytes,
        [Alias('PixelCount')]
        [int32]$TargetFileSizeInByte = 100000,
        [ValidateRange(0,100)]
        [int64]$jpegQuality = 90
    )

    function Get-ImageCodecInfo ($Image) {

        $guid = $Image.RawFormat.Guid
    
        foreach ($codec in [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()) {
            if ($codec.FormatID -eq $guid) {
                $codec
            }
        }
    
    }
    
    function Get-ImageCodecFilenameExtension ($ImageCodecInfo) {
    
        ($ImageCodecInfo.FilenameExtension.split(';'))[0].trimStart('*').toLower()
    
    }


    # run image processing if there is EITHER an image file OR an array of bytes provided
    if ($InputFile -xor $ImageBytes.Count -gt 0) {

        # Add System.Drawing assembly
        try {
            Add-Type -AssemblyName System.Drawing
        } catch {
            Throw 'Assembly System.Drawing could not be loaded in Function Resize-Image.'
        }

#region GETIMAGE
        if ($InputFile) {

            # Get image from file
            $img = [System.Drawing.Image]::FromFile((Get-Item $InputFile))

        } else {

            # Get image from byte array using a MemoryStream
            $InputStream = [System.IO.MemoryStream]::New($ImageBytes)
            $img = [System.Drawing.Image]::FromStream($InputStream)
            $InputStream.Dispose()

        }
#endregion GETIMAGE

#region SIZECALCULATION
        # calculate "colorless" size (= max. pixel count); the bitmap class below will
        # create a 32bit image, so we can devide by 4 bytes and ignore all other formats
        $maxpixel = [int32][math]::Round( $TargetFileSizeInByte / 4, 0, 1)

        # we only need to resize if the current picture is larger than our desired output size
        if ($img.Width * $img.Height -gt $maxpixel) {
            # calculate x:y ratio
            $ratio  = [double]$img.Width / $img.Height
        
            # calculate maximum sidelengths
            $Width  = [int32][math]::Round( [math]::Sqrt($maxpixel*$ratio), 0, 1)
            $Height = [int32][math]::Round( [math]::Sqrt($maxpixel/$ratio), 0, 1)      

        } else {

            $Width  = $img.Width
            $Height = $img.Height

        }

        # Create bitmap in desired size
        $bmp = [System.Drawing.Bitmap]::New($Width,$Height)
        
        # create graphics object from bitmap to set processing quality
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        
        # redraw bitmap of image in desired size
        $gfx.DrawImage($img,[System.Drawing.Rectangle]::New(0,0,$Width,$Height))
#endregion SIZECALCULATION

#region OUTIMAGE

        # get format and codec info of original image
        $ImageCodecInfo     = Get-ImageCodecInfo $img
        # extract matching file extension from codec info
        $ImageFileExtension = Get-ImageCodecFilenameExtension $ImageCodecInfo

        # create encoder from QualityGuid
        $QualityGuid = [System.Drawing.Imaging.Encoder]::Quality.Guid
        $Encoder = [System.Drawing.Imaging.Encoder]::new($QualityGuid)
    
        # create encoder parameters object with one array element which holds the jpeg quality
        $EncParams =  [System.Drawing.Imaging.EncoderParameters]::new()
        $EncParams.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new($Encoder, $jpegQuality)
        
        $img.Dispose()

        if ($OutputFile) {
            
            # change OutputFileExtension if not matchin ImageFormat
            $ofExt = ($OutputFile -split '(?=\.)')[-1]
            if ($ofExt -ne $ImageFileExtension) {
                $OutputFile = $OutputFile -replace "$ofExt$",$ImageFileExtension
            }
            # Save the image to disk
            $bmp.Save($OutputFile, $ImageCodecInfo, $EncParams)

        } else {

            # Return image as byte array using the imageformat of the original image
            $OutputStream = [System.IO.MemoryStream]::New()
            $bmp.Save($OutputStream, $ImageCodecInfo, $EncParams)
            ,$OutputStream.ToArray()

            $OutputStream.Dispose()

        }
#region OUTIMAGE        

    } else {

        if ($InputFile -and $ImageBytes.Count -gt 0) {
            Throw 'Only one input allowed. InputFile or InputBytes.'
        } else {
            Throw 'No input provided. Please provide an InputFile or ImageBytes.'
        }
        
    }

}
