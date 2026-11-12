<#
=============================================================================
 diagnostico-gui.ps1  ·  Dashboard WPF de diagnostico.ps1 (testing-loki)

 Lo mismo que diagnostico.ps1 (ping real, puertos, http, 4 estados,
 monitoreo continuo) pero con una ventana grafica: panel de OPCIONES a la
 izquierda (como el menu de LOKI, pero con controles en vez de numeros) y
 el dashboard en vivo a la derecha (tarjetas, tabla, actividad, alertas).

 USO:
   .\diagnostico-gui.ps1

 No usa parametros: todo se configura en la ventana. Las reglas de
 autorizacion y el tope de 64 IP por rango son las mismas que en
 diagnostico.ps1 / auditar-rango.ps1 (ninguno de esos dos se toca aca).
=============================================================================
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# =============================================================================
# 1) FUNCIONES DE RED (las mismas pruebas que diagnostico.ps1, sin cambios
#    en la logica: solo lo que se MUESTRA cambia en esta version).
# =============================================================================
function IP-A-Numero { param($ip)
  $partes = $ip.Split('.')
  if ($partes.Count -ne 4) { return $null }
  foreach ($x in $partes) { if (-not ($x -match '^\d{1,3}$') -or [int]$x -gt 255) { return $null } }
  return ([uint32]$partes[0] -shl 24) -bor ([uint32]$partes[1] -shl 16) -bor ([uint32]$partes[2] -shl 8) -bor [uint32]$partes[3]
}
function Numero-A-IP { param($n)
  "{0}.{1}.{2}.{3}" -f (($n -shr 24) -band 255), (($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255) }

function Prueba-Ping { param($ip, $msTimeout = 2000)
  try {
    $pinger = New-Object System.Net.NetworkInformation.Ping
    $resp = $pinger.Send($ip, $msTimeout)
    $ms = [int]$resp.RoundtripTime
    switch ($resp.Status) {
      "Success" { return @{ Estado = "ok"; Ms = $ms } }
      "TimedOut" { return @{ Estado = "timeout"; Ms = $msTimeout } }
      default { return @{ Estado = "rechazado"; Ms = $ms; Detalle = "$($resp.Status)" } }
    }
  } catch { return @{ Estado = "error"; Ms = 0; Detalle = $_.Exception.Message } }
}
function Prueba-Puerto { param($ip, $puerto, $msTimeout = 2500)
  $cron = [System.Diagnostics.Stopwatch]::StartNew()
  $cliente = New-Object System.Net.Sockets.TcpClient
  try {
    $pendiente = $cliente.BeginConnect($ip, $puerto, $null, $null)
    $llego = $pendiente.AsyncWaitHandle.WaitOne($msTimeout, $false)
    if (-not $llego) { $cron.Stop(); return @{ Estado = "timeout"; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) } }
    try { $cliente.EndConnect($pendiente); $cron.Stop(); return @{ Estado = "abierto"; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) } }
    catch { $cron.Stop(); return @{ Estado = "rechazado"; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) } }
  } catch { $cron.Stop(); return @{ Estado = "error"; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) } }
  finally { try { if ($cliente.Connected) { $cliente.Close() } else { $cliente.Dispose() } } catch {} }
}
function Prueba-HTTP { param($url, $msTimeout = 6000)
  $cron = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $resp = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec ([int]($msTimeout/1000)) -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Stop
    $cron.Stop(); return @{ Codigo = [int]$resp.StatusCode; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) }
  } catch {
    $cron.Stop()
    if ($_.Exception.Response) { try { return @{ Codigo = [int]$_.Exception.Response.StatusCode; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) } } catch {} }
    return @{ Codigo = 0; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) }
  }
}
function Clasificar { param($ping, $puertosRes)
  if ($ping.Estado -eq "error") { return "ERROR" }
  if ($ping.Estado -eq "ok") { return "ONLINE" }
  $hayAbierto   = $puertosRes | Where-Object { $_.Estado -eq "abierto" }
  $hayRechazado = $puertosRes | Where-Object { $_.Estado -eq "rechazado" }
  $hayError     = $puertosRes | Where-Object { $_.Estado -eq "error" }
  if ($hayAbierto)   { return "ONLINE" }
  if ($hayRechazado) { return "ONLINE" }
  if ($ping.Estado -eq "rechazado") { return "OFFLINE" }
  if ($hayError -and $puertosRes.Count -eq $hayError.Count) { return "ERROR" }
  return "TIMEOUT"
}

# =============================================================================
# 2) VENTANA (XAML) — panel de OPCIONES a la izquierda, dashboard a la derecha
# =============================================================================
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="testing-loki · diagnostico" Width="1180" Height="760" MinWidth="900" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="#0A0E0C" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#E8FFF0"/></Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#16201B"/>
      <Setter Property="Foreground" Value="#E8FFF0"/>
      <Setter Property="BorderBrush" Value="#2A3A33"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#0E1512"/>
      <Setter Property="Foreground" Value="#E8FFF0"/>
      <Setter Property="BorderBrush" Value="#2A3A33"/>
      <Setter Property="Padding" Value="6,5"/>
      <Setter Property="CaretBrush" Value="#39FF78"/>
    </Style>
    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#E8FFF0"/></Style>
    <Style TargetType="RadioButton"><Setter Property="Foreground" Value="#E8FFF0"/><Setter Property="Margin" Value="0,0,0,6"/></Style>
    <Style x:Key="EtiqSidebar" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11"/><Setter Property="Foreground" Value="#8FA398"/><Setter Property="Margin" Value="0,10,0,4"/>
    </Style>
    <Style x:Key="Tarjeta" TargetType="Border">
      <Setter Property="Background" Value="#121815"/><Setter Property="CornerRadius" Value="12"/><Setter Property="Padding" Value="14"/>
      <Setter Property="Effect"><Setter.Value><DropShadowEffect BlurRadius="18" ShadowDepth="2" Opacity="0.35" Color="#000000"/></Setter.Value></Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="56"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="30"/>
    </Grid.RowDefinitions>

    <!-- ===================== ENCABEZADO ===================== -->
    <Border Grid.Row="0" Background="#101512" BorderBrush="#1E2A24" BorderThickness="0,0,0,1">
      <DockPanel LastChildFill="True" Margin="16,0">
        <Border Width="30" Height="30" CornerRadius="8" Background="#0C447C" VerticalAlignment="Center">
          <TextBlock Text="◆" FontSize="14" Foreground="#378ADD" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="testing-loki" FontSize="14" FontWeight="SemiBold"/>
          <TextBlock Text="diagnostico de conectividad" FontSize="10" Foreground="#8FA398"/>
        </StackPanel>
        <TextBlock x:Name="TxtHora" DockPanel.Dock="Right" Text="00:00:00" FontSize="16" VerticalAlignment="Center" Margin="16,0,0,0"/>
        <StackPanel DockPanel.Dock="Right" VerticalAlignment="Center" Margin="0,0,10,0">
          <TextBlock x:Name="TxtFecha" Text="" FontSize="10" Foreground="#8FA398" HorizontalAlignment="Right"/>
        </StackPanel>
        <Border DockPanel.Dock="Right" Background="#854F0B" CornerRadius="7" Padding="9,3" Margin="0,0,10,0" VerticalAlignment="Center">
          <TextBlock Text="v2.0" FontSize="10" Foreground="#FAC775"/>
        </Border>
        <Border x:Name="BadgeVivo" DockPanel.Dock="Right" Background="#2C0000" CornerRadius="7" Padding="9,3" Margin="0,0,10,0" VerticalAlignment="Center" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="PuntoVivo" Width="7" Height="7" Fill="#E24B4A" VerticalAlignment="Center"/>
            <TextBlock Text=" en vivo" FontSize="10" Foreground="#F09595" Margin="4,0,0,0"/>
          </StackPanel>
        </Border>
        <TextBlock Text=""/>
      </DockPanel>
    </Border>

    <!-- ===================== CUERPO ===================== -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="300"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- SIDEBAR: OPCIONES (como el menu de LOKI) -->
      <Border Grid.Column="0" Background="#101512" BorderBrush="#1E2A24" BorderThickness="0,0,1,0">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="16,14,16,14">
            <TextBlock Text="OPCIONES" FontSize="12" FontWeight="SemiBold" Foreground="#B98CFF"/>

            <TextBlock Text="objetivo" Style="{StaticResource EtiqSidebar}"/>
            <RadioButton x:Name="RbUnica" Content="IP unica" IsChecked="True" GroupName="modo"/>
            <RadioButton x:Name="RbRango" Content="Rango de IP" GroupName="modo"/>

            <TextBlock Text="ip objetivo" Style="{StaticResource EtiqSidebar}"/>
            <TextBox x:Name="TxtObjetivo" Text="203.0.113.10"/>

            <TextBlock Text="rango (desde / hasta)" Style="{StaticResource EtiqSidebar}"/>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <TextBox x:Name="TxtDesde" Grid.Column="0" Text="192.168.1.1" IsEnabled="False"/>
              <TextBox x:Name="TxtHasta" Grid.Column="2" Text="192.168.1.20" IsEnabled="False"/>
            </Grid>

            <TextBlock Text="puertos (separados por coma)" Style="{StaticResource EtiqSidebar}"/>
            <TextBox x:Name="TxtPuertos" Text="22,80,443,3306"/>

            <TextBlock Text="monitoreo" Style="{StaticResource EtiqSidebar}"/>
            <CheckBox x:Name="ChkMonitoreo" Content="Monitoreo continuo"/>
            <Grid Margin="0,6,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="80"/></Grid.ColumnDefinitions>
              <TextBlock Text="intervalo (segundos)" VerticalAlignment="Center" FontSize="12"/>
              <TextBox x:Name="TxtIntervalo" Grid.Column="1" Text="30" IsEnabled="False"/>
            </Grid>

            <TextBlock Text="reportes" Style="{StaticResource EtiqSidebar}"/>
            <CheckBox x:Name="ChkReporte" Content="Guardar TXT y CSV" IsChecked="True"/>
            <Grid Margin="0,6,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/></Grid.ColumnDefinitions>
              <TextBox x:Name="TxtCarpeta" Grid.Column="0" Text=".\reportes" IsReadOnly="True"/>
              <Button x:Name="BtnCarpeta" Grid.Column="1" Content="..." Margin="4,0,0,0"/>
            </Grid>

            <Border Background="#412402" CornerRadius="8" Padding="10" Margin="0,16,0,0">
              <StackPanel>
                <TextBlock Text="⚠ autorizacion" FontSize="11" FontWeight="SemiBold" Foreground="#FAC775"/>
                <TextBlock Text="Cada IP (o cada IP del rango) tiene que ser tuya o estar autorizada. Un bloque compartido con otros clientes de tu proveedor NO queda autorizado por ser dueno de una sola IP de ese bloque." FontSize="10" Foreground="#E8DCC0" TextWrapping="Wrap" Margin="0,6,0,8"/>
                <CheckBox x:Name="ChkAutorizo" Content="Confirmo que es mio o estoy autorizado" FontWeight="SemiBold"/>
              </StackPanel>
            </Border>

            <TextBlock x:Name="TxtError" Text="" FontSize="11" Foreground="#E24B4A" TextWrapping="Wrap" Margin="0,10,0,0"/>

            <Button x:Name="BtnIniciar" Content="▶ Iniciar diagnostico" Background="#27500A" BorderBrush="#3B6D11" Margin="0,16,0,8" Padding="10,10"/>
            <Button x:Name="BtnDetener" Content="■ Detener" Background="#501313" BorderBrush="#791F1F" IsEnabled="False" Padding="10,10"/>
          </StackPanel>
        </ScrollViewer>
      </Border>

      <!-- DASHBOARD -->
      <Grid Grid.Column="1" Margin="16">
        <Grid.RowDefinitions>
          <RowDefinition Height="86"/>
          <RowDefinition Height="56"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="150"/>
        </Grid.RowDefinitions>

        <!-- tarjetas -->
        <Grid Grid.Row="0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="8"/>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="8"/>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="8"/>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="8"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0" Style="{StaticResource Tarjeta}">
            <StackPanel><TextBlock Text="total ip" FontSize="11" Foreground="#8FA398"/><TextBlock x:Name="TxtTotal" Text="0" FontSize="26" FontWeight="SemiBold" Margin="0,4,0,0"/></StackPanel>
          </Border>
          <Border Grid.Column="2" Background="#173404" CornerRadius="12" Padding="14">
            <StackPanel><TextBlock Text="online" FontSize="11" Foreground="#97C459"/><TextBlock x:Name="TxtOnline" Text="0" FontSize="26" FontWeight="SemiBold" Foreground="#C0DD97" Margin="0,4,0,0"/></StackPanel>
          </Border>
          <Border Grid.Column="4" Background="#501313" CornerRadius="12" Padding="14">
            <StackPanel><TextBlock Text="offline" FontSize="11" Foreground="#F09595"/><TextBlock x:Name="TxtOffline" Text="0" FontSize="26" FontWeight="SemiBold" Foreground="#F7C1C1" Margin="0,4,0,0"/></StackPanel>
          </Border>
          <Border Grid.Column="6" Background="#412402" CornerRadius="12" Padding="14">
            <StackPanel><TextBlock Text="timeout" FontSize="11" Foreground="#EF9F27"/><TextBlock x:Name="TxtTimeout" Text="0" FontSize="26" FontWeight="SemiBold" Foreground="#FAC775" Margin="0,4,0,0"/></StackPanel>
          </Border>
          <Border Grid.Column="8" Style="{StaticResource Tarjeta}">
            <StackPanel><TextBlock Text="puertos abiertos" FontSize="11" Foreground="#8FA398"/><TextBlock x:Name="TxtPuertosAbiertos" Text="0" FontSize="26" FontWeight="SemiBold" Margin="0,4,0,0"/></StackPanel>
          </Border>
        </Grid>

        <!-- progreso -->
        <Border Grid.Row="1" Background="#121815" CornerRadius="10" Padding="12,8" Margin="0,10,0,0">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Grid Grid.Row="0">
              <TextBlock x:Name="TxtProgresoIp" Text="en espera" FontSize="12" HorizontalAlignment="Left"/>
              <TextBlock x:Name="TxtProgresoPct" Text="0 / 0 · 0%" FontSize="12" Foreground="#8FA398" HorizontalAlignment="Right"/>
            </Grid>
            <Border Grid.Row="1" Background="#0E1512" Height="7" CornerRadius="4" Margin="0,6,0,0">
              <Border x:Name="BarraProgreso" Background="#378ADD" Height="7" CornerRadius="4" HorizontalAlignment="Left" Width="0"/>
            </Border>
          </Grid>
        </Border>

        <!-- tabla -->
        <Border Grid.Row="2" Background="#121815" CornerRadius="12" Padding="4" Margin="0,10,0,0">
          <DataGrid x:Name="Grilla" AutoGenerateColumns="False" IsReadOnly="True" Background="Transparent" Foreground="#E8FFF0"
                    BorderThickness="0" RowBackground="Transparent" AlternatingRowBackground="#0E1512" HeadersVisibility="Column"
                    GridLinesVisibility="None" CanUserResizeRows="False" RowHeight="30">
            <DataGrid.ColumnHeaderStyle>
              <Style TargetType="DataGridColumnHeader">
                <Setter Property="Background" Value="#0E1512"/><Setter Property="Foreground" Value="#8FA398"/>
                <Setter Property="FontSize" Value="11"/><Setter Property="Padding" Value="10,8"/><Setter Property="BorderThickness" Value="0"/>
              </Style>
            </DataGrid.ColumnHeaderStyle>
            <DataGrid.CellStyle>
              <Style TargetType="DataGridCell">
                <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="10,4"/>
                <Setter Property="Template">
                  <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                      <Border Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}"><ContentPresenter VerticalAlignment="Center"/></Border>
                    </ControlTemplate>
                  </Setter.Value>
                </Setter>
              </Style>
            </DataGrid.CellStyle>
            <DataGrid.Columns>
              <DataGridTextColumn Header="ip" Binding="{Binding IP}" Width="1.3*"/>
              <DataGridTemplateColumn Header="estado" Width="1*">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <Border Background="{Binding EstadoFondo}" CornerRadius="6" Padding="8,2" HorizontalAlignment="Left">
                      <TextBlock Text="{Binding Estado}" Foreground="{Binding EstadoTexto}" FontSize="11" FontWeight="SemiBold"/>
                    </Border>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="latencia" Binding="{Binding Latencia}" Width="0.8*"/>
              <DataGridTextColumn Header="puertos" Binding="{Binding Puertos}" Width="1.4*"/>
              <DataGridTextColumn Header="http" Binding="{Binding Http}" Width="0.6*"/>
              <DataGridTextColumn Header="ultima vez" Binding="{Binding Hora}" Width="0.9*"/>
            </DataGrid.Columns>
          </DataGrid>
        </Border>

        <!-- actividad + alertas -->
        <Grid Grid.Row="3" Margin="0,10,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="1.3*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
          <Border Grid.Column="0" Background="#121815" CornerRadius="12" Padding="12">
            <DockPanel>
              <TextBlock DockPanel.Dock="Top" Text="actividad reciente" FontSize="11" FontWeight="SemiBold" Foreground="#5AA6FF" Margin="0,0,0,6"/>
              <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="PanelActividad"/></ScrollViewer>
            </DockPanel>
          </Border>
          <Border Grid.Column="2" Background="#412402" CornerRadius="12" Padding="12">
            <DockPanel>
              <TextBlock DockPanel.Dock="Top" Text="⚠ alertas activas" FontSize="11" FontWeight="SemiBold" Foreground="#FAC775" Margin="0,0,0,6"/>
              <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="PanelAlertas"/></ScrollViewer>
            </DockPanel>
          </Border>
        </Grid>
      </Grid>
    </Grid>

    <!-- ===================== PIE ===================== -->
    <Border Grid.Row="2" Background="#101512" BorderBrush="#1E2A24" BorderThickness="0,1,0,0">
      <DockPanel Margin="16,0">
        <TextBlock x:Name="TxtPie" Text="listo" FontSize="11" Foreground="#8FA398" VerticalAlignment="Center"/>
        <TextBlock DockPanel.Dock="Right" Text="solo IP propias o autorizadas" FontSize="11" Foreground="#5F6B64" VerticalAlignment="Center" HorizontalAlignment="Right"/>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

$lector = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($lector)

# Atajo para encontrar controles por nombre
$C = @{}
foreach ($nombre in @("TxtHora","TxtFecha","BadgeVivo","PuntoVivo","RbUnica","RbRango","TxtObjetivo","TxtDesde","TxtHasta",
  "TxtPuertos","ChkMonitoreo","TxtIntervalo","ChkReporte","TxtCarpeta","BtnCarpeta","ChkAutorizo","TxtError",
  "BtnIniciar","BtnDetener","TxtTotal","TxtOnline","TxtOffline","TxtTimeout","TxtPuertosAbiertos",
  "TxtProgresoIp","TxtProgresoPct","BarraProgreso","Grilla","PanelActividad","PanelAlertas","TxtPie")) {
  $C[$nombre] = $window.FindName($nombre)
}

# =============================================================================
# 3) ESTADO COMPARTIDO Y UTILIDADES DE UI
# =============================================================================
$script:filas = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
$C.Grilla.ItemsSource = $script:filas
$script:filaPorIp = @{}
$script:alertaPorIp = @{}
$script:estado = [hashtable]::Synchronized(@{ Detener = $false; Corriendo = $false })
$script:inicioCorrida = $null

function Color-Por-Estado { param($estado)
  switch ($estado) {
    "ONLINE"  { @{ Fondo = "#173404"; Texto = "#C0DD97" }; break }
    "OFFLINE" { @{ Fondo = "#501313"; Texto = "#F7C1C1" }; break }
    "TIMEOUT" { @{ Fondo = "#412402"; Texto = "#FAC775" }; break }
    default   { @{ Fondo = "#501313"; Texto = "#F7C1C1" } }
  }
}
function Upsert-Fila { param($ip, $estado, $latenciaMs, $puertosTxt, $httpTxt)
  $colorEstado = Color-Por-Estado $estado
  $hora = Get-Date -Format "HH:mm:ss"
  if ($script:filaPorIp.ContainsKey($ip)) {
    $f = $script:filaPorIp[$ip]
    $f.Estado = $estado; $f.EstadoFondo = $colorEstado.Fondo; $f.EstadoTexto = $colorEstado.Texto
    $f.Latencia = "$latenciaMs ms"; $f.Puertos = $puertosTxt; $f.Http = $httpTxt; $f.Hora = $hora
    [System.Windows.Data.CollectionViewSource]::GetDefaultView($C.Grilla.ItemsSource).Refresh()
  } else {
    $f = [PSCustomObject]@{ IP=$ip; Estado=$estado; EstadoFondo=$colorEstado.Fondo; EstadoTexto=$colorEstado.Texto; Latencia="$latenciaMs ms"; Puertos=$puertosTxt; Http=$httpTxt; Hora=$hora }
    $script:filaPorIp[$ip] = $f
    $script:filas.Add($f)
  }
}
function Agregar-Actividad { param($icono, $color, $texto)
  $hora = Get-Date -Format "HH:mm:ss"
  $linea = New-Object System.Windows.Controls.StackPanel
  $linea.Orientation = "Horizontal"; $linea.Margin = "0,2,0,2"
  $pt = New-Object System.Windows.Controls.TextBlock
  $pt.Text = "●"; $pt.Foreground = $color; $pt.FontSize = 11; $pt.Margin = "0,0,6,0"; $pt.VerticalAlignment = "Center"
  $th = New-Object System.Windows.Controls.TextBlock
  $th.Text = $hora; $th.Foreground = "#5F6B64"; $th.FontSize = 11; $th.Width = 58
  $tt = New-Object System.Windows.Controls.TextBlock
  $tt.Text = $texto; $tt.FontSize = 12; $tt.TextWrapping = "Wrap"
  [void]$linea.Children.Add($pt); [void]$linea.Children.Add($th); [void]$linea.Children.Add($tt)
  $C.PanelActividad.Children.Insert(0, $linea)
  while ($C.PanelActividad.Children.Count -gt 14) { $C.PanelActividad.Children.RemoveAt($C.PanelActividad.Children.Count - 1) }
}
function Refrescar-Alertas {
  $C.PanelAlertas.Children.Clear()
  if ($script:alertaPorIp.Count -eq 0) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = "sin alertas"; $t.FontSize = 12; $t.Foreground = "#E8DCC0"
    [void]$C.PanelAlertas.Children.Add($t)
    return
  }
  foreach ($kv in $script:alertaPorIp.GetEnumerator()) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $kv.Value; $t.FontSize = 12; $t.Foreground = "#E8DCC0"; $t.TextWrapping = "Wrap"; $t.Margin = "0,2,0,2"
    [void]$C.PanelAlertas.Children.Add($t)
  }
}
function Marcar-Alerta { param($ip, $texto) $script:alertaPorIp[$ip] = $texto; Refrescar-Alertas }
function Quitar-Alerta { param($ip) if ($script:alertaPorIp.ContainsKey($ip)) { $script:alertaPorIp.Remove($ip); Refrescar-Alertas } }

# Reloj en vivo
$relojTimer = New-Object System.Windows.Threading.DispatcherTimer
$relojTimer.Interval = [TimeSpan]::FromSeconds(1)
$relojTimer.Add_Tick({
  $C.TxtHora.Text = Get-Date -Format "HH:mm:ss"
  $C.TxtFecha.Text = Get-Date -Format "d MMM yyyy"
})
$relojTimer.Start()

# Punto "en vivo" parpadeando (solo visible mientras corre algo)
$pulsoTimer = New-Object System.Windows.Threading.DispatcherTimer
$pulsoTimer.Interval = [TimeSpan]::FromMilliseconds(600)
$script:pulsoOn = $true
$pulsoTimer.Add_Tick({
  $script:pulsoOn = -not $script:pulsoOn
  $C.PuntoVivo.Opacity = if ($script:pulsoOn) { 1.0 } else { 0.25 }
})

# =============================================================================
# 4) VALIDACION Y ARRANQUE/PARADA (reglas de autorizacion y tope de 64 iguales
#    a diagnostico.ps1 / auditar-rango.ps1, traducidas a controles de ventana)
# =============================================================================
$C.RbUnica.Add_Checked({ $C.TxtObjetivo.IsEnabled = $true; $C.TxtDesde.IsEnabled = $false; $C.TxtHasta.IsEnabled = $false })
$C.RbRango.Add_Checked({ $C.TxtObjetivo.IsEnabled = $false; $C.TxtDesde.IsEnabled = $true; $C.TxtHasta.IsEnabled = $true })
$C.ChkMonitoreo.Add_Checked({ $C.TxtIntervalo.IsEnabled = $true })
$C.ChkMonitoreo.Add_Unchecked({ $C.TxtIntervalo.IsEnabled = $false })
$C.BtnCarpeta.Add_Click({
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  if ($dlg.ShowDialog() -eq "OK") { $C.TxtCarpeta.Text = $dlg.SelectedPath }
})

function Validar-Y-Armar {
  $C.TxtError.Text = ""
  $puertosTxt = $C.TxtPuertos.Text.Split(',') | ForEach-Object { $_.Trim() }
  $puertos = @()
  foreach ($p in $puertosTxt) {
    if (-not ($p -match '^\d+$') -or [int]$p -lt 1 -or [int]$p -gt 65535) { $C.TxtError.Text = "Puerto invalido: '$p'"; return $null }
    $puertos += [int]$p
  }
  $ips = @()
  if ($C.RbUnica.IsChecked) {
    $n = IP-A-Numero $C.TxtObjetivo.Text.Trim()
    if ($null -eq $n) { $C.TxtError.Text = "La IP objetivo no es valida."; return $null }
    $ips = @($C.TxtObjetivo.Text.Trim())
  } else {
    $nd = IP-A-Numero $C.TxtDesde.Text.Trim(); $nh = IP-A-Numero $C.TxtHasta.Text.Trim()
    if ($null -eq $nd -or $null -eq $nh) { $C.TxtError.Text = "Desde/Hasta no son IP validas."; return $null }
    if ($nh -lt $nd) { $C.TxtError.Text = "Hasta tiene que ser igual o mayor que Desde."; return $null }
    $total = $nh - $nd + 1
    if ($total -gt 64) { $C.TxtError.Text = "Ese rango tiene $total direcciones: el tope por corrida es 64."; return $null }
    for ($n = $nd; $n -le $nh; $n++) { $ips += Numero-A-IP $n }
  }
  if (-not $C.ChkAutorizo.IsChecked) { $C.TxtError.Text = "Tenes que confirmar la autorizacion antes de iniciar."; return $null }
  $intervalo = 30
  if ($C.ChkMonitoreo.IsChecked) {
    if (-not ($C.TxtIntervalo.Text -match '^\d+$') -or [int]$C.TxtIntervalo.Text -lt 3) { $C.TxtError.Text = "El intervalo tiene que ser un numero (minimo 3s)."; return $null }
    $intervalo = [int]$C.TxtIntervalo.Text
  }
  if (-not $C.RbUnica.IsChecked) {
    $r = [System.Windows.MessageBox]::Show(
      "Vas a revisar $($ips.Count) direccion(es), de $($C.TxtDesde.Text) a $($C.TxtHasta.Text).`n`nConfirmas que TODAS son tuyas o estan autorizadas?",
      "Confirmar autorizacion", "YesNo", "Warning")
    if ($r -ne "Yes") { $C.TxtError.Text = "Cancelado: no se confirmo el rango."; return $null }
  }
  return @{ Ips = $ips; Puertos = $puertos; Monitoreo = [bool]$C.ChkMonitoreo.IsChecked; Intervalo = $intervalo
            Reporte = [bool]$C.ChkReporte.IsChecked; Carpeta = $C.TxtCarpeta.Text }
}

function Guardar-Reportes-GUI { param($carpeta, $filas)
  try {
    New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    $sello = Get-Date -Format "yyyyMMdd-HHmmss"
    $rutaTxt = Join-Path $carpeta "diagnostico-gui-$sello.txt"
    $rutaCsv = Join-Path $carpeta "diagnostico-gui-$sello.csv"
    $lin = @("DIAGNOSTICO (GUI) - testing-loki", "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "")
    foreach ($f in $filas) { $lin += "$($f.IP) | $($f.Estado) | $($f.Latencia) | $($f.Puertos) | http $($f.Http) | $($f.Hora)" }
    Set-Content -Path $rutaTxt -Value $lin -Encoding UTF8
    $filas | Select-Object IP,Estado,Latencia,Puertos,Http,Hora | Export-Csv -Path $rutaCsv -NoTypeInformation -Encoding UTF8
    return $rutaTxt
  } catch { return $null }
}

# =============================================================================
# 5) MOTOR DE ESCANEO EN SEGUNDO PLANO (runspace aparte, no congela la ventana)
# =============================================================================
$script:runspace = $null
$script:psCorriendo = $null

$scriptEscaneo = {
  param($window, $C, $ips, $puertos, $monitoreo, $intervalo, $reporte, $carpeta, $estado,
        $fnUpsert, $fnActividad, $fnMarcarAlerta, $fnQuitarAlerta, $fnIpNum, $fnNumIp, $fnPing, $fnPuerto, $fnHttp, $fnClasif, $fnReportes)

  function Marcar-Contadores { param($cont)
    $window.Dispatcher.Invoke([action]{
      $C.TxtOnline.Text = "$($cont.ONLINE)"; $C.TxtOffline.Text = "$($cont.OFFLINE)"; $C.TxtTimeout.Text = "$($cont.TIMEOUT)"
    })
  }

  $vuelta = 0
  $previo = @{}
  do {
    $vuelta++
    $inicio = Get-Date
    $cont = @{ ONLINE = 0; OFFLINE = 0; TIMEOUT = 0; ERROR = 0 }
    $puertosAbiertosTotal = 0
    $filasFinal = @()

    for ($idx = 0; $idx -lt $ips.Count; $idx++) {
      if ($estado.Detener) { break }
      $ip = $ips[$idx]
      $pct = [math]::Round((($idx) / [math]::Max(1,$ips.Count)) * 100)
      $window.Dispatcher.Invoke([action]{
        $C.TxtProgresoIp.Text = "escaneando $ip"
        $C.TxtProgresoPct.Text = "$idx / $($ips.Count) · $pct%"
        $C.BarraProgreso.Width = [double]($C.BarraProgreso.Parent.ActualWidth * ($pct/100.0))
      })

      $ping = & $fnPing $ip
      $puertosRes = @()
      $abiertos = @(); $httpTxt = "—"
      foreach ($p in $puertos) {
        if ($estado.Detener) { break }
        $r = & $fnPuerto $ip $p
        $puertosRes += [pscustomobject]@{ Puerto=$p; Estado=$r.Estado; Ms=$r.Ms }
        if ($r.Estado -eq "abierto") {
          $abiertos += $p; $puertosAbiertosTotal++
          if ($p -in 80,8080) { $h = & $fnHttp "http://$ip`:$p"; $httpTxt = "$($h.Codigo)" }
          elseif ($p -in 443,8443) { $h = & $fnHttp "https://$ip`:$p"; $httpTxt = "$($h.Codigo)" }
        }
      }
      $estadoIp = & $fnClasif $ping $puertosRes
      $cont[$estadoIp]++
      $puertosTxt = if ($abiertos.Count -gt 0) { $abiertos -join ", " } else { "—" }

      $window.Dispatcher.Invoke([action]{
        & $fnUpsert $ip $estadoIp $ping.Ms $puertosTxt $httpTxt
        $C.TxtTotal.Text = "$($ips.Count)"
        $C.TxtPuertosAbiertos.Text = "$puertosAbiertosTotal"
        switch ($estadoIp) {
          "ONLINE"  { & $fnActividad "" "#97C459" "$ip responde · $($ping.Ms) ms"; & $fnQuitarAlerta $ip }
          "OFFLINE" { & $fnActividad "" "#F09595" "$ip inalcanzable"; & $fnMarcarAlerta $ip "$ip esta OFFLINE" }
          "TIMEOUT" { & $fnActividad "" "#EF9F27" "$ip sin respuesta (timeout)"; & $fnMarcarAlerta $ip "$ip no responde (timeout)" }
          "ERROR"   { & $fnActividad "" "#F09595" "$ip error al probar"; & $fnMarcarAlerta $ip "$ip dio error al probar" }
        }
        if ($previo.ContainsKey($ip) -and $previo[$ip] -ne $estadoIp) {
          if ($estadoIp -eq "ONLINE") { & $fnActividad "" "#97C459" "$ip volvio ($($previo[$ip]) -> ONLINE)" }
        }
      })
      $previo[$ip] = $estadoIp
      $filasFinal += [pscustomobject]@{ IP=$ip; Estado=$estadoIp; Latencia="$($ping.Ms) ms"; Puertos=$puertosTxt; Http=$httpTxt; Hora=(Get-Date -Format "HH:mm:ss") }
      Marcar-Contadores $cont
    }

    $dur = (Get-Date) - $inicio
    $window.Dispatcher.Invoke([action]{
      $C.TxtProgresoIp.Text = if ($estado.Detener) { "detenido" } else { "pasada completa" }
      $C.TxtProgresoPct.Text = "$($ips.Count) / $($ips.Count) · 100%"
      $C.BarraProgreso.Width = [double]$C.BarraProgreso.Parent.ActualWidth
      $C.TxtPie.Text = "vuelta $vuelta · duracion $([math]::Round($dur.TotalSeconds,1)) s · ON:$($cont.ONLINE) OFF:$($cont.OFFLINE) TO:$($cont.TIMEOUT) ERR:$($cont.ERROR)"
    })
    if ($reporte -and $filasFinal.Count -gt 0) { & $fnReportes $carpeta $filasFinal }

    if ($monitoreo -and -not $estado.Detener) {
      $restante = $intervalo
      while ($restante -gt 0 -and -not $estado.Detener) { Start-Sleep -Milliseconds 250; $restante -= 0.25 }
    }
  } while ($monitoreo -and -not $estado.Detener)

  $window.Dispatcher.Invoke([action]{
    $estado.Corriendo = $false
    $C.BtnIniciar.IsEnabled = $true
    $C.BtnDetener.IsEnabled = $false
    $C.BadgeVivo.Visibility = "Collapsed"
    $pulsoTimerRef = $script:pulsoTimerGlobal
  })
}

$C.BtnIniciar.Add_Click({
  $cfg = Validar-Y-Armar
  if ($null -eq $cfg) { return }
  $C.TxtError.Text = ""
  $script:estado.Detener = $false
  $script:estado.Corriendo = $true
  $script:filas.Clear(); $script:filaPorIp.Clear(); $script:alertaPorIp.Clear(); Refrescar-Alertas
  $C.PanelActividad.Children.Clear()
  $C.BtnIniciar.IsEnabled = $false
  $C.BtnDetener.IsEnabled = $true
  $C.BadgeVivo.Visibility = "Visible"
  $pulsoTimer.Start()

  $runspace = [runspacefactory]::CreateRunspace()
  $runspace.ApartmentState = "MTA"; $runspace.ThreadOptions = "ReuseThread"; $runspace.Open()
  $ps = [powershell]::Create()
  $ps.Runspace = $runspace
  [void]$ps.AddScript($scriptEscaneo).AddArgument($window).AddArgument($C).AddArgument($cfg.Ips).AddArgument($cfg.Puertos).
    AddArgument($cfg.Monitoreo).AddArgument($cfg.Intervalo).AddArgument($cfg.Reporte).AddArgument($cfg.Carpeta).AddArgument($script:estado).
    AddArgument(${function:Upsert-Fila}).AddArgument(${function:Agregar-Actividad}).AddArgument(${function:Marcar-Alerta}).AddArgument(${function:Quitar-Alerta}).
    AddArgument(${function:IP-A-Numero}).AddArgument(${function:Numero-A-IP}).AddArgument(${function:Prueba-Ping}).AddArgument(${function:Prueba-Puerto}).
    AddArgument(${function:Prueba-HTTP}).AddArgument(${function:Clasificar}).AddArgument(${function:Guardar-Reportes-GUI})
  $script:runspace = $runspace
  $script:psCorriendo = $ps
  [void]$ps.BeginInvoke()
})

$C.BtnDetener.Add_Click({
  $script:estado.Detener = $true
  $C.BtnDetener.IsEnabled = $false
  $C.TxtProgresoIp.Text = "deteniendo..."
  $pulsoTimer.Stop(); $C.PuntoVivo.Opacity = 1
})

$window.Add_Closing({
  $script:estado.Detener = $true
  Start-Sleep -Milliseconds 200
  if ($script:psCorriendo) { try { $script:psCorriendo.Stop() } catch {} }
  if ($script:runspace) { try { $script:runspace.Close() } catch {} }
})

Refrescar-Alertas
$C.TxtHora.Text = Get-Date -Format "HH:mm:ss"
$C.TxtFecha.Text = Get-Date -Format "d MMM yyyy"

[void]$window.ShowDialog()
