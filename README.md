<h3>ParrotFlowerPower</h3>
<ul>
  <u><b>ParrotFlowerPower - Plant Sensor</b></u>
  <br>
  This module can be used to read data from Parrot Flower Power sensors with bluetooth 4.0 Low Energy.<br><br>
  <b>Requirements:</b><br>
  Gattool is required to use this module. Be sure that bluez is installed (sudo apt-get install bluez).
  <br><br>
  <b>The Parrot Flower Power sensor can measure the following values:</b>
  <ul>
    <li>temperature</li>
    <li>soil moisture</li>
    <li>light</li>
    <li>fertilizer (not yet supported by the module because the formula to convert the raw value into a useful value is not publicly available)</li>
  </ul>
  <br><br>
  <b>Installation:</b>
  <ul>
    <li>be sure that bluez is installed: sudo apt-get install bluez</li>
    <li>add the new update site: update add http://raw.githubusercontent.com/mumpitzstuff/fhem-ParrotFlowerPower/master/controls_parrotflowerpower.txt</li>
    <li>run the update and wait until finished: update all</li>
    <li>restart fhem: shutdown restart</li>
    <li>define a new device: define &lt;name of plant&gt; ParrotFlowerPower &lt;mac address of sensor e.g. AA:BB:CC:DD:EE:FF&gt;</li>
  </ul>
</ul>
