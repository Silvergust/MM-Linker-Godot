[![](http://img.youtube.com/vi/KLEHdDST6gA/0.jpg)](http://www.youtube.com/watch?v=KLEHdDST6gA "Video Title")

# Material Maker Linker

These are the files required to modify Material Maker so as to be able to connect with [Material Maker Linker](https://github.com/Silvergust/MM-Linker) and connect Blender with MM.
Material Maker is a material generation tool by [RodZill4](https://github.com/RodZill4/material-maker), which as-is do not allow transfer of data between the user's programs. Applying these files to a MM project allows you to do just that. The important parts are:

* Server.gd, the heart of the program, a script that establishes a server and handles reception, interpretation and emition of data.
* blender_link.tscn, a rudimentary UI to activate the server.
* blender_linker.gd and PortLineEdit.gd, to handle the UI's logic.

In addition, it also requires increasing the maximum data output size (Project Settings -> Network -> Limits -> Max. Output Buffer) depending on the size of data to send (mainly texture size, so working with 1024x1024 images requires slightly more than 4 MB, or a "4200" KB input.

You'll also need a way to access the MML server menu, you can just attach a node to the main screen but a cleaner solution is to add these lines to main_window.gd:
As part of the `MENU` definition
```
	{ menu="Tools/Blender Link", command="blender_link" },
```
Elsewhere:  
```
func blender_link() -> void:
	add_child(load("res://mml_linker/blender_link.tscn").instance())
```
# Binaries
If you want to avoid all that you can just use the latest binary from the [release page](https://github.com/Silvergust/MM-Linker-Godot/releases/tag/Main_Release).

# Donations
If you find this software useful, please consider an Ethereum donation to the following address: 0xe04946Dfe2cdc98A0c812671B3492a4B21c70c11

If you find the original Material Maker useful as-is, also consider a donation to that project.
