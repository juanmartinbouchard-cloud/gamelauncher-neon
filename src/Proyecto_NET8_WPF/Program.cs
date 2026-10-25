using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

[assembly: AssemblyTitle("GameLauncher Neon")]
[assembly: AssemblyDescription("Biblioteca y Lanzador de Juegos para Windows")]
[assembly: AssemblyCompany("GameLauncher Neon")]
[assembly: AssemblyProduct("GameLauncher Neon")]
[assembly: AssemblyCopyright("Copyright © 2026 GameLauncher Neon")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace GameLauncher
{
    // =========================================================================
    // 1. MODELOS DE DATOS Y CONFIGURACIÓN
    // =========================================================================
    public class GameItem : INotifyPropertyChanged
    {
        private string _id;
        private string _title;
        private string _executablePath;
        private string _arguments;
        private string _customCoverPath;
        private bool _isFavorite;
        private string _lastPlayedIso;
        private int _playCount;
        private ImageSource _displayIcon;

        public GameItem()
        {
            _id = Guid.NewGuid().ToString("N");
            _title = "";
            _executablePath = "";
            _arguments = "";
            _customCoverPath = "";
            _isFavorite = false;
            _lastPlayedIso = "";
            _playCount = 0;
        }

        public string Id
        {
            get { return _id; }
            set { _id = value; OnPropertyChanged("Id"); }
        }

        public string Title
        {
            get { return _title; }
            set { _title = value; OnPropertyChanged("Title"); }
        }

        public string ExecutablePath
        {
            get { return _executablePath; }
            set
            {
                _executablePath = value;
                OnPropertyChanged("ExecutablePath");
                OnPropertyChanged("IsAvailable");
                OnPropertyChanged("StatusText");
            }
        }

        public string Arguments
        {
            get { return _arguments; }
            set { _arguments = value; OnPropertyChanged("Arguments"); }
        }

        public string CustomCoverPath
        {
            get { return _customCoverPath; }
            set { _customCoverPath = value; OnPropertyChanged("CustomCoverPath"); }
        }

        public bool IsFavorite
        {
            get { return _isFavorite; }
            set
            {
                _isFavorite = value;
                OnPropertyChanged("IsFavorite");
                OnPropertyChanged("FavoriteSymbol");
            }
        }

        public string LastPlayedIso
        {
            get { return _lastPlayedIso; }
            set
            {
                _lastPlayedIso = value;
                OnPropertyChanged("LastPlayedIso");
                OnPropertyChanged("LastPlayedText");
            }
        }

        public int PlayCount
        {
            get { return _playCount; }
            set
            {
                _playCount = value;
                OnPropertyChanged("PlayCount");
                OnPropertyChanged("LastPlayedText");
            }
        }

        [ScriptIgnore]
        public bool IsAvailable
        {
            get { return !string.IsNullOrWhiteSpace(_executablePath) && File.Exists(_executablePath); }
        }

        [ScriptIgnore]
        public string StatusText
        {
            get { return IsAvailable ? "● Disponible" : "● Ruta no disponible"; }
        }

        [ScriptIgnore]
        public string FavoriteSymbol
        {
            get { return _isFavorite ? "★" : "☆"; }
        }

        [ScriptIgnore]
        public string LastPlayedText
        {
            get
            {
                if (string.IsNullOrWhiteSpace(_lastPlayedIso))
                    return "Nunca iniciado";
                DateTime dt;
                if (DateTime.TryParse(_lastPlayedIso, out dt))
                    return string.Format("Última vez: {0:dd/MM/yyyy HH:mm} ({1}x)", dt, _playCount);
                return "Nunca iniciado";
            }
        }

        [ScriptIgnore]
        public ImageSource DisplayIcon
        {
            get { return _displayIcon; }
            set { _displayIcon = value; OnPropertyChanged("DisplayIcon"); }
        }

        public void RefreshStatus()
        {
            OnPropertyChanged("IsAvailable");
            OnPropertyChanged("StatusText");
        }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name)
        {
            PropertyChangedEventHandler handler = PropertyChanged;
            if (handler != null)
                handler(this, new PropertyChangedEventArgs(name));
        }
    }

    public class LaunchHistoryEntry
    {
        public string GameId { get; set; }
        public string GameTitle { get; set; }
        public string ExecutablePath { get; set; }
        public string TimestampIso { get; set; }

        public LaunchHistoryEntry()
        {
            GameId = "";
            GameTitle = "";
            ExecutablePath = "";
            TimestampIso = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        }
    }

    public class AppDataContainer
    {
        public List<GameItem> Games { get; set; }
        public List<LaunchHistoryEntry> History { get; set; }
        public bool MinimizeOnLaunch { get; set; }
        public bool HighContrastBorders { get; set; }

        public AppDataContainer()
        {
            Games = new List<GameItem>();
            History = new List<LaunchHistoryEntry>();
            MinimizeOnLaunch = true;
            HighContrastBorders = false;
        }
    }

    // =========================================================================
    // 2. SERVICIOS (LOGS, ALMACENAMIENTO LOCALAPPDATA, ICONOS, INICIO WINDOWS)
    // =========================================================================
    public static class LoggerService
    {
        public static string AppDataFolder
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "GameLauncherNeon");
            }
        }

        public static string LogFilePath
        {
            get { return Path.Combine(AppDataFolder, "logs", "app.log"); }
        }

        public static void Info(string message)
        {
            WriteLog("INFO", message);
        }

        public static void Error(string message, Exception ex)
        {
            string detail = ex != null ? string.Format("{0} | {1}: {2}", message, ex.GetType().Name, ex.Message) : message;
            WriteLog("ERROR", detail);
        }

        private static void WriteLog(string level, string message)
        {
            try
            {
                string dir = Path.GetDirectoryName(LogFilePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                    Directory.CreateDirectory(dir);

                string line = string.Format("[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}{3}", DateTime.Now, level, message, Environment.NewLine);
                File.AppendAllText(LogFilePath, line, Encoding.UTF8);
            }
            catch
            {
            }
        }
    }

    public static class StorageService
    {
        public static string LibraryFilePath
        {
            get { return Path.Combine(LoggerService.AppDataFolder, "library.json"); }
        }

        public static AppDataContainer Load()
        {
            try
            {
                if (!Directory.Exists(LoggerService.AppDataFolder))
                    Directory.CreateDirectory(LoggerService.AppDataFolder);

                if (!File.Exists(LibraryFilePath))
                    return new AppDataContainer();

                string json = File.ReadAllText(LibraryFilePath, Encoding.UTF8);
                JavaScriptSerializer serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = int.MaxValue;
                AppDataContainer data = serializer.Deserialize<AppDataContainer>(json);
                return data ?? new AppDataContainer();
            }
            catch (Exception ex)
            {
                LoggerService.Error("Error al cargar library.json", ex);
                return new AppDataContainer();
            }
        }

        public static void Save(AppDataContainer data)
        {
            try
            {
                if (!Directory.Exists(LoggerService.AppDataFolder))
                    Directory.CreateDirectory(LoggerService.AppDataFolder);

                JavaScriptSerializer serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = int.MaxValue;
                string json = serializer.Serialize(data);

                string tempFile = LibraryFilePath + ".tmp";
                File.WriteAllText(tempFile, json, Encoding.UTF8);
                if (File.Exists(LibraryFilePath))
                    File.Delete(LibraryFilePath);
                File.Move(tempFile, LibraryFilePath);
            }
            catch (Exception ex)
            {
                LoggerService.Error("Error al guardar library.json", ex);
            }
        }

        public static void ExportLibrary(string destinationFile, AppDataContainer data)
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = int.MaxValue;
            string json = serializer.Serialize(data);
            File.WriteAllText(destinationFile, json, Encoding.UTF8);
            LoggerService.Info("Biblioteca exportada a: " + destinationFile);
        }

        public static AppDataContainer ImportLibrary(string sourceFile)
        {
            string json = File.ReadAllText(sourceFile, Encoding.UTF8);
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = int.MaxValue;
            AppDataContainer data = serializer.Deserialize<AppDataContainer>(json);
            if (data == null || data.Games == null)
                throw new InvalidDataException("El archivo seleccionado no contiene una biblioteca válida de GameLauncher.");
            LoggerService.Info("Biblioteca importada desde: " + sourceFile);
            return data;
        }
    }

    public static class IconExtractorService
    {
        public static ImageSource LoadImageOrIcon(string executablePath, string customCoverPath)
        {
            if (!string.IsNullOrWhiteSpace(customCoverPath) && File.Exists(customCoverPath))
            {
                try
                {
                    BitmapImage bitmap = new BitmapImage();
                    bitmap.BeginInit();
                    bitmap.CacheOption = BitmapCacheOption.OnLoad;
                    bitmap.UriSource = new Uri(customCoverPath, UriKind.Absolute);
                    bitmap.DecodePixelWidth = 300;
                    bitmap.EndInit();
                    bitmap.Freeze();
                    return bitmap;
                }
                catch (Exception ex)
                {
                    LoggerService.Error("No se pudo cargar carátula personalizada: " + customCoverPath, ex);
                }
            }

            if (!string.IsNullOrWhiteSpace(executablePath) && File.Exists(executablePath))
            {
                try
                {
                    using (System.Drawing.Icon ico = System.Drawing.Icon.ExtractAssociatedIcon(executablePath))
                    {
                        if (ico != null)
                        {
                            ImageSource img = Imaging.CreateBitmapSourceFromHIcon(
                                ico.Handle,
                                Int32Rect.Empty,
                                BitmapSizeOptions.FromEmptyOptions());
                            img.Freeze();
                            return img;
                        }
                    }
                }
                catch (Exception ex)
                {
                    LoggerService.Error("No se pudo extraer el icono del ejecutable: " + executablePath, ex);
                }
            }

            return null;
        }
    }

    public static class StartupService
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AppKeyName = "GameLauncherNeon";

        public static bool IsStartupEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey, false))
                {
                    if (key == null) return false;
                    return key.GetValue(AppKeyName) != null;
                }
            }
            catch (Exception ex)
            {
                LoggerService.Error("Error al leer registro de inicio", ex);
                return false;
            }
        }

        public static void SetStartup(bool enable)
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey, true))
            {
                if (key == null) return;
                if (enable)
                {
                    string exePath = Process.GetCurrentProcess().MainModule.FileName;
                    key.SetValue(AppKeyName, "\"" + exePath + "\"");
                    LoggerService.Info("Inicio automático con Windows activado.");
                }
                else
                {
                    if (key.GetValue(AppKeyName) != null)
                    {
                        key.DeleteValue(AppKeyName, false);
                        LoggerService.Info("Inicio automático con Windows desactivado.");
                    }
                }
            }
        }
    }

    // =========================================================================
    // 3. INTERFAZ GRÁFICA PRINCIPAL Y LÓGICA DE CONTROL (WPF NEON)
    // =========================================================================
    public class MainWindowController
    {
        public Window MainWindow { get; private set; }

        private AppDataContainer _appData;
        private bool _filterFavoritesOnly;
        private GameItem _editingGame;

        // Controles enlazados desde XAML
        private Border _mainWindowBorder;
        private Border _topTitleBar;
        private TextBlock _topStatusText;
        private TextBlock _maxRestoreIcon;
        private TextBlock _statsTotalText;
        private TextBlock _statsAvailableText;
        private TextBlock _statsMissingText;
        private Grid _libraryView;
        private Grid _historyView;
        private ScrollViewer _settingsView;
        private TextBox _searchBox;
        private TextBlock _searchPlaceholder;
        private CheckBox _onlyAvailableCheck;
        private ComboBox _sortComboBox;
        private ItemsControl _gamesItemsControl;
        private Border _emptyStatePanel;
        private ListBox _historyListBox;
        private CheckBox _startupWithWindowsCheck;
        private CheckBox _minimizeOnLaunchCheck;
        private CheckBox _highContrastBorderCheck;
        private TextBlock _localDataPathText;
        private TextBlock _footerStatusText;

        // Modal Añadir / Editar
        private Border _gameModalOverlay;
        private TextBlock _modalHeaderTitle;
        private TextBox _modalExePathBox;
        private TextBox _modalTitleBox;
        private TextBox _modalCoverPathBox;
        private TextBox _modalArgsBox;

        public MainWindowController()
        {
            _appData = new AppDataContainer();
            _filterFavoritesOnly = false;
            _editingGame = null;
            BuildWindow();
            LoadState();
        }

        private void BuildWindow()
        {
            string xaml = GetWindowXaml();
            MainWindow = (Window)XamlReader.Parse(xaml);

            // Ventana sin bordes clásicos con soporte de redimensionado nativo (CanResizeWithGrip)

            // Cargar icono de ventana si existe en Assets\app.ico
            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string icoPath = Path.Combine(baseDir, "Assets", "app.ico");
                if (File.Exists(icoPath))
                {
                    MainWindow.Icon = new BitmapImage(new Uri(icoPath, UriKind.Absolute));
                }
            }
            catch
            {
            }

            // Localizar controles
            _mainWindowBorder = (Border)MainWindow.FindName("MainWindowBorder");
            _topTitleBar = (Border)MainWindow.FindName("TopTitleBar");
            _topStatusText = (TextBlock)MainWindow.FindName("TopStatusText");
            _maxRestoreIcon = (TextBlock)MainWindow.FindName("MaxRestoreIcon");
            _statsTotalText = (TextBlock)MainWindow.FindName("StatsTotalText");
            _statsAvailableText = (TextBlock)MainWindow.FindName("StatsAvailableText");
            _statsMissingText = (TextBlock)MainWindow.FindName("StatsMissingText");
            _libraryView = (Grid)MainWindow.FindName("LibraryView");
            _historyView = (Grid)MainWindow.FindName("HistoryView");
            _settingsView = (ScrollViewer)MainWindow.FindName("SettingsView");
            _searchBox = (TextBox)MainWindow.FindName("SearchBox");
            _searchPlaceholder = (TextBlock)MainWindow.FindName("SearchPlaceholder");
            _onlyAvailableCheck = (CheckBox)MainWindow.FindName("OnlyAvailableCheck");
            _sortComboBox = (ComboBox)MainWindow.FindName("SortComboBox");
            _gamesItemsControl = (ItemsControl)MainWindow.FindName("GamesItemsControl");
            _emptyStatePanel = (Border)MainWindow.FindName("EmptyStatePanel");
            _historyListBox = (ListBox)MainWindow.FindName("HistoryListBox");
            _startupWithWindowsCheck = (CheckBox)MainWindow.FindName("StartupWithWindowsCheck");
            _minimizeOnLaunchCheck = (CheckBox)MainWindow.FindName("MinimizeOnLaunchCheck");
            _highContrastBorderCheck = (CheckBox)MainWindow.FindName("HighContrastBorderCheck");
            _localDataPathText = (TextBlock)MainWindow.FindName("LocalDataPathText");
            _footerStatusText = (TextBlock)MainWindow.FindName("FooterStatusText");

            _gameModalOverlay = (Border)MainWindow.FindName("GameModalOverlay");
            _modalHeaderTitle = (TextBlock)MainWindow.FindName("ModalHeaderTitle");
            _modalExePathBox = (TextBox)MainWindow.FindName("ModalExePathBox");
            _modalTitleBox = (TextBox)MainWindow.FindName("ModalTitleBox");
            _modalCoverPathBox = (TextBox)MainWindow.FindName("ModalCoverPathBox");
            _modalArgsBox = (TextBox)MainWindow.FindName("ModalArgsBox");

            // Eventos de barra superior
            _topTitleBar.MouseLeftButtonDown += (s, e) =>
            {
                if (e.ClickCount == 2)
                    ToggleMaximize();
                else if (e.LeftButton == MouseButtonState.Pressed)
                    MainWindow.DragMove();
            };

            ((Button)MainWindow.FindName("MinimizeBtn")).Click += (s, e) => MainWindow.WindowState = WindowState.Minimized;
            ((Button)MainWindow.FindName("MaximizeBtn")).Click += (s, e) => ToggleMaximize();
            ((Button)MainWindow.FindName("CloseBtn")).Click += (s, e) => MainWindow.Close();

            // Eventos de navegación lateral
            ((Button)MainWindow.FindName("AddGameSidebarBtn")).Click += OpenAddGameModal;
            ((Button)MainWindow.FindName("EmptyAddGameBtn")).Click += OpenAddGameModal;
            ((Button)MainWindow.FindName("NavAllBtn")).Click += (s, e) =>
            {
                _filterFavoritesOnly = false;
                ShowSection("Library");
                RefreshGamesList();
                _footerStatusText.Text = "Mostrando todos los juegos de la biblioteca.";
            };
            ((Button)MainWindow.FindName("NavFavBtn")).Click += (s, e) =>
            {
                _filterFavoritesOnly = true;
                ShowSection("Library");
                RefreshGamesList();
                _footerStatusText.Text = "Mostrando tus juegos favoritos.";
            };
            ((Button)MainWindow.FindName("NavHistoryBtn")).Click += (s, e) =>
            {
                RefreshHistoryList();
                ShowSection("History");
                _footerStatusText.Text = "Mostrando el historial de juegos iniciados.";
            };
            ((Button)MainWindow.FindName("NavSettingsBtn")).Click += (s, e) =>
            {
                ShowSection("Settings");
                _footerStatusText.Text = "Configuración y copias de seguridad.";
            };
            ((Button)MainWindow.FindName("VerifyPathsBtn")).Click += VerifyAllPaths;

            // Eventos de filtrado y ordenación
            _searchBox.TextChanged += (s, e) => RefreshGamesList();
            _onlyAvailableCheck.Checked += (s, e) => RefreshGamesList();
            _onlyAvailableCheck.Unchecked += (s, e) => RefreshGamesList();
            _sortComboBox.SelectionChanged += (s, e) => RefreshGamesList();

            // Eventos delegados de las tarjetas de juegos (Play, Edit, Remove, Fav)
            _gamesItemsControl.AddHandler(Button.ClickEvent, new RoutedEventHandler(OnCardButtonClicked));

            // Eventos del Modal
            ((Button)MainWindow.FindName("BrowseExeBtn")).Click += BrowseExe;
            ((Button)MainWindow.FindName("BrowseCoverBtn")).Click += BrowseCover;
            ((Button)MainWindow.FindName("CancelModalBtn")).Click += (s, e) =>
            {
                _gameModalOverlay.Visibility = Visibility.Collapsed;
                _editingGame = null;
            };
            ((Button)MainWindow.FindName("SaveModalBtn")).Click += SaveModalGame;

            // Eventos de Historial y Configuración
            ((Button)MainWindow.FindName("ClearHistoryBtn")).Click += (s, e) =>
            {
                _appData.History.Clear();
                StorageService.Save(_appData);
                RefreshHistoryList();
                _footerStatusText.Text = "Historial de sesiones limpiado.";
            };

            _startupWithWindowsCheck.Click += (s, e) =>
            {
                try
                {
                    StartupService.SetStartup(_startupWithWindowsCheck.IsChecked == true);
                    _footerStatusText.Text = _startupWithWindowsCheck.IsChecked == true
                        ? "Inicio automático con Windows activado."
                        : "Inicio automático con Windows desactivado.";
                }
                catch (Exception ex)
                {
                    MessageBox.Show("No se pudo actualizar el inicio con Windows:\n" + ex.Message, "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            };

            RoutedEventHandler settingsChanged = (s, e) =>
            {
                _appData.MinimizeOnLaunch = _minimizeOnLaunchCheck.IsChecked == true;
                _appData.HighContrastBorders = _highContrastBorderCheck.IsChecked == true;
                StorageService.Save(_appData);
                ApplyVisualSettings();
            };
            _minimizeOnLaunchCheck.Click += settingsChanged;
            _highContrastBorderCheck.Click += settingsChanged;

            ((Button)MainWindow.FindName("ExportLibraryBtn")).Click += ExportLibrary;
            ((Button)MainWindow.FindName("ImportLibraryBtn")).Click += ImportLibrary;
            ((Button)MainWindow.FindName("OpenDataFolderBtn")).Click += OpenAppDataFolder;
        }

        private void ToggleMaximize()
        {
            MainWindow.WindowState = MainWindow.WindowState == WindowState.Maximized
                ? WindowState.Normal
                : WindowState.Maximized;
            _maxRestoreIcon.Text = MainWindow.WindowState == WindowState.Maximized ? "❐" : "▢";
        }

        private void LoadState()
        {
            _appData = StorageService.Load();
            foreach (GameItem g in _appData.Games)
            {
                g.DisplayIcon = IconExtractorService.LoadImageOrIcon(g.ExecutablePath, g.CustomCoverPath);
            }

            _startupWithWindowsCheck.IsChecked = StartupService.IsStartupEnabled();
            _minimizeOnLaunchCheck.IsChecked = _appData.MinimizeOnLaunch;
            _highContrastBorderCheck.IsChecked = _appData.HighContrastBorders;
            _localDataPathText.Text = "Ubicación de datos: " + LoggerService.AppDataFolder;

            ApplyVisualSettings();
            RefreshGamesList();
            RefreshHistoryList();
        }

        private void ApplyVisualSettings()
        {
            string colorHex = _appData.HighContrastBorders ? "#06B6D4" : "#2D2B52";
            _mainWindowBorder.BorderBrush = (SolidColorBrush)new BrushConverter().ConvertFromString(colorHex);
        }

        private void ShowSection(string section)
        {
            _libraryView.Visibility = section == "Library" ? Visibility.Visible : Visibility.Collapsed;
            _historyView.Visibility = section == "History" ? Visibility.Visible : Visibility.Collapsed;
            _settingsView.Visibility = section == "Settings" ? Visibility.Visible : Visibility.Collapsed;
        }

        private void RefreshGamesList()
        {
            string query = _searchBox.Text != null ? _searchBox.Text.Trim() : "";
            _searchPlaceholder.Visibility = string.IsNullOrEmpty(query) ? Visibility.Visible : Visibility.Collapsed;

            IEnumerable<GameItem> filtered = _appData.Games;

            if (_filterFavoritesOnly)
                filtered = filtered.Where(g => g.IsFavorite);

            if (_onlyAvailableCheck.IsChecked == true)
                filtered = filtered.Where(g => g.IsAvailable);

            if (!string.IsNullOrWhiteSpace(query))
                filtered = filtered.Where(g => g.Title != null && g.Title.IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0);

            int sortIdx = _sortComboBox.SelectedIndex;
            if (sortIdx == 1)
                filtered = filtered.OrderByDescending(g => g.LastPlayedIso ?? "").ThenBy(g => g.Title);
            else if (sortIdx == 2)
                filtered = filtered.OrderByDescending(g => g.PlayCount).ThenBy(g => g.Title);
            else if (sortIdx == 3)
                filtered = filtered.OrderByDescending(g => g.IsAvailable).ThenBy(g => g.Title);
            else
                filtered = filtered.OrderBy(g => g.Title);

            List<GameItem> list = filtered.ToList();
            _gamesItemsControl.ItemsSource = list;
            _emptyStatePanel.Visibility = list.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

            UpdateStatusIndicators();
        }

        private void UpdateStatusIndicators()
        {
            int total = _appData.Games.Count;
            int avail = _appData.Games.Count(g => g.IsAvailable);
            int missing = total - avail;

            _statsTotalText.Text = string.Format("Total: {0} {1}", total, total == 1 ? "juego" : "juegos");
            _statsAvailableText.Text = string.Format("Disponibles: {0}", avail);
            _statsMissingText.Text = string.Format("No disponibles: {0}", missing);

            GameItem lastGame = _appData.Games
                .Where(g => !string.IsNullOrWhiteSpace(g.LastPlayedIso))
                .OrderByDescending(g => g.LastPlayedIso)
                .FirstOrDefault();

            _topStatusText.Text = lastGame != null
                ? "Último jugado: " + lastGame.Title
                : string.Format("Biblioteca activa ({0} disponibles)", avail);
        }

        private void RefreshHistoryList()
        {
            _historyListBox.Items.Clear();
            if (_appData.History.Count == 0)
            {
                _historyListBox.Items.Add("Aún no se ha iniciado ningún juego desde GameLauncher.");
                return;
            }

            foreach (LaunchHistoryEntry entry in _appData.History.AsEnumerable().Reverse().Take(100))
            {
                _historyListBox.Items.Add(string.Format("[{0}]  ▶  {1}   ({2})", entry.TimestampIso, entry.GameTitle, entry.ExecutablePath));
            }
        }

        private void OnCardButtonClicked(object sender, RoutedEventArgs e)
        {
            DependencyObject dep = e.OriginalSource as DependencyObject;
            while (dep != null && !(dep is Button))
            {
                dep = VisualTreeHelper.GetParent(dep);
            }
            Button btn = dep as Button;
            if (btn == null) return;

            GameItem game = btn.Tag as GameItem;
            if (game == null) return;

            if (btn.Uid == "Play")
                PlayGame(game);
            else if (btn.Uid == "Edit")
                OpenEditGameModal(game);
            else if (btn.Uid == "Remove")
                RemoveGame(game);
            else if (btn.Uid == "Fav")
            {
                game.IsFavorite = !game.IsFavorite;
                StorageService.Save(_appData);
                RefreshGamesList();
            }
        }

        private void OpenAddGameModal(object sender, RoutedEventArgs e)
        {
            _editingGame = null;
            _modalHeaderTitle.Text = "AÑADIR JUEGO A LA BIBLIOTECA";
            _modalExePathBox.Text = "";
            _modalTitleBox.Text = "";
            _modalCoverPathBox.Text = "";
            _modalArgsBox.Text = "";
            _gameModalOverlay.Visibility = Visibility.Visible;
        }

        private void OpenEditGameModal(GameItem game)
        {
            _editingGame = game;
            _modalHeaderTitle.Text = "EDITAR JUEGO / ACTUALIZAR RUTA";
            _modalExePathBox.Text = game.ExecutablePath;
            _modalTitleBox.Text = game.Title;
            _modalCoverPathBox.Text = game.CustomCoverPath;
            _modalArgsBox.Text = game.Arguments;
            _gameModalOverlay.Visibility = Visibility.Visible;
        }

        private void BrowseExe(object sender, RoutedEventArgs e)
        {
            OpenFileDialog dlg = new OpenFileDialog
            {
                Title = "Seleccionar archivo ejecutable del juego (.exe)",
                Filter = "Ejecutables de Windows (*.exe)|*.exe|Todos los archivos (*.*)|*.*",
                CheckFileExists = true
            };

            if (dlg.ShowDialog() == true)
            {
                _modalExePathBox.Text = dlg.FileName;
                if (string.IsNullOrWhiteSpace(_modalTitleBox.Text))
                {
                    try
                    {
                        FileVersionInfo info = FileVersionInfo.GetVersionInfo(dlg.FileName);
                        string candidate = !string.IsNullOrWhiteSpace(info.ProductName)
                            ? info.ProductName.Trim()
                            : Path.GetFileNameWithoutExtension(dlg.FileName);
                        _modalTitleBox.Text = candidate;
                    }
                    catch
                    {
                        _modalTitleBox.Text = Path.GetFileNameWithoutExtension(dlg.FileName);
                    }
                }
            }
        }

        private void BrowseCover(object sender, RoutedEventArgs e)
        {
            OpenFileDialog dlg = new OpenFileDialog
            {
                Title = "Seleccionar imagen de carátula (Opcional)",
                Filter = "Imágenes (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp",
                CheckFileExists = true
            };
            if (dlg.ShowDialog() == true)
            {
                _modalCoverPathBox.Text = dlg.FileName;
            }
        }

        private void SaveModalGame(object sender, RoutedEventArgs e)
        {
            string exePath = (_modalExePathBox.Text ?? "").Trim().Trim('"');
            string title = (_modalTitleBox.Text ?? "").Trim();
            string coverPath = (_modalCoverPathBox.Text ?? "").Trim().Trim('"');
            string args = (_modalArgsBox.Text ?? "").Trim();

            if (string.IsNullOrWhiteSpace(exePath))
            {
                MessageBox.Show("Debes seleccionar o indicar la ruta del archivo ejecutable (.exe) del juego.", "Datos incompletos", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            if (string.IsNullOrWhiteSpace(title))
            {
                title = Path.GetFileNameWithoutExtension(exePath);
            }

            if (!File.Exists(exePath))
            {
                MessageBoxResult confirm = MessageBox.Show(
                    "El archivo ejecutable indicado no existe actualmente en esa ruta.\n¿Deseas guardar la entrada de todos modos como 'Ruta no disponible'?",
                    "Ruta no encontrada",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Question);
                if (confirm != MessageBoxResult.Yes) return;
            }

            if (_editingGame == null)
            {
                GameItem newGame = new GameItem
                {
                    Title = title,
                    ExecutablePath = exePath,
                    CustomCoverPath = coverPath,
                    Arguments = args
                };
                newGame.DisplayIcon = IconExtractorService.LoadImageOrIcon(newGame.ExecutablePath, newGame.CustomCoverPath);
                _appData.Games.Add(newGame);
                LoggerService.Info("Juego añadido: " + title + " (" + exePath + ")");
                _footerStatusText.Text = "Juego añadido: " + title;
            }
            else
            {
                _editingGame.Title = title;
                _editingGame.ExecutablePath = exePath;
                _editingGame.CustomCoverPath = coverPath;
                _editingGame.Arguments = args;
                _editingGame.DisplayIcon = IconExtractorService.LoadImageOrIcon(_editingGame.ExecutablePath, _editingGame.CustomCoverPath);
                _editingGame.RefreshStatus();
                LoggerService.Info("Juego editado: " + title + " (" + exePath + ")");
                _footerStatusText.Text = "Datos actualizados para: " + title;
            }

            StorageService.Save(_appData);
            _gameModalOverlay.Visibility = Visibility.Collapsed;
            _editingGame = null;
            RefreshGamesList();
        }

        private void PlayGame(GameItem game)
        {
            game.RefreshStatus();
            if (!game.IsAvailable)
            {
                MessageBoxResult res = MessageBox.Show(
                    string.Format("No se puede iniciar «{0}» porque el archivo ejecutable ya no existe en la ruta:\n\n{1}\n\n¿Deseas actualizar la ruta del juego ahora?", game.Title, game.ExecutablePath),
                    "Ruta no disponible",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning);
                if (res == MessageBoxResult.Yes)
                    OpenEditGameModal(game);
                return;
            }

            try
            {
                string workingDir = Path.GetDirectoryName(game.ExecutablePath);
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = game.ExecutablePath,
                    Arguments = game.Arguments ?? "",
                    WorkingDirectory = !string.IsNullOrEmpty(workingDir) ? workingDir : Environment.CurrentDirectory,
                    UseShellExecute = true
                };

                Process.Start(psi);

                game.LastPlayedIso = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                game.PlayCount++;
                _appData.History.Add(new LaunchHistoryEntry
                {
                    GameId = game.Id,
                    GameTitle = game.Title,
                    ExecutablePath = game.ExecutablePath,
                    TimestampIso = game.LastPlayedIso
                });

                StorageService.Save(_appData);
                RefreshGamesList();
                LoggerService.Info("Juego iniciado: " + game.Title);
                _footerStatusText.Text = "En ejecución: " + game.Title;

                if (_appData.MinimizeOnLaunch)
                    MainWindow.WindowState = WindowState.Minimized;
            }
            catch (Exception ex)
            {
                LoggerService.Error("Error al iniciar juego: " + game.Title, ex);
                MessageBox.Show(
                    string.Format("No se pudo iniciar «{0}».\n\nMotivo devuelto por Windows:\n{1}\n\nComprueba que el archivo no esté dañado ni requiera un lanzador externo.", game.Title, ex.Message),
                    "Error al iniciar el juego",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
        }

        private void RemoveGame(GameItem game)
        {
            MessageBoxResult confirm = MessageBox.Show(
                string.Format("¿Quieres quitar «{0}» de tu biblioteca de GameLauncher?\n\nNota importante: Esta acción SOLO quita la tarjeta de la biblioteca. Los archivos originales del juego en tu ordenador NO se borran ni se modifican.", game.Title),
                "Quitar juego de la biblioteca",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (confirm == MessageBoxResult.Yes)
            {
                _appData.Games.Remove(game);
                StorageService.Save(_appData);
                LoggerService.Info("Juego quitado de la biblioteca (archivos intactos): " + game.Title);
                _footerStatusText.Text = "Se quitó '" + game.Title + "' de la biblioteca.";
                RefreshGamesList();
            }
        }

        private void VerifyAllPaths(object sender, RoutedEventArgs e)
        {
            int missing = 0;
            foreach (GameItem g in _appData.Games)
            {
                g.RefreshStatus();
                g.DisplayIcon = IconExtractorService.LoadImageOrIcon(g.ExecutablePath, g.CustomCoverPath);
                if (!g.IsAvailable) missing++;
            }

            RefreshGamesList();
            _footerStatusText.Text = missing == 0
                ? "Verificación completada: todas las rutas están disponibles."
                : string.Format("Verificación completada: {0} ruta(s) no se encuentran.", missing);

            MessageBox.Show(
                missing == 0
                    ? "Todos los juegos de tu biblioteca tienen rutas válidas y están listos para jugar."
                    : string.Format("Se detectaron {0} juego(s) cuya ruta ya no existe.\nPulsa el botón de editar (✎) en su tarjeta para actualizar la ubicación del archivo .exe.", missing),
                "Verificación de Biblioteca",
                MessageBoxButton.OK,
                missing == 0 ? MessageBoxImage.Information : MessageBoxImage.Warning);
        }

        private void ExportLibrary(object sender, RoutedEventArgs e)
        {
            SaveFileDialog dlg = new SaveFileDialog
            {
                Title = "Exportar biblioteca de GameLauncher",
                Filter = "Archivo JSON (*.json)|*.json",
                FileName = string.Format("GameLauncher_Backup_{0:yyyyMMdd}.json", DateTime.Now)
            };

            if (dlg.ShowDialog() == true)
            {
                try
                {
                    StorageService.ExportLibrary(dlg.FileName, _appData);
                    MessageBox.Show("Biblioteca exportada correctamente.", "Exportación completada", MessageBoxButton.OK, MessageBoxImage.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Error al exportar la biblioteca:\n" + ex.Message, "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        private void ImportLibrary(object sender, RoutedEventArgs e)
        {
            OpenFileDialog dlg = new OpenFileDialog
            {
                Title = "Importar biblioteca de GameLauncher",
                Filter = "Archivo JSON (*.json)|*.json"
            };

            if (dlg.ShowDialog() == true)
            {
                try
                {
                    AppDataContainer imported = StorageService.ImportLibrary(dlg.FileName);
                    int added = 0;
                    foreach (GameItem g in imported.Games)
                    {
                        bool exists = _appData.Games.Any(x => string.Equals(x.ExecutablePath, g.ExecutablePath, StringComparison.OrdinalIgnoreCase));
                        if (!exists)
                        {
                            g.DisplayIcon = IconExtractorService.LoadImageOrIcon(g.ExecutablePath, g.CustomCoverPath);
                            _appData.Games.Add(g);
                            added++;
                        }
                    }
                    StorageService.Save(_appData);
                    RefreshGamesList();
                    MessageBox.Show(string.Format("Importación finalizada. Se añadieron {0} juego(s) nuevo(s).", added), "Importación completada", MessageBoxButton.OK, MessageBoxImage.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Error al importar el archivo:\n" + ex.Message, "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        private void OpenAppDataFolder(object sender, RoutedEventArgs e)
        {
            try
            {
                if (!Directory.Exists(LoggerService.AppDataFolder))
                    Directory.CreateDirectory(LoggerService.AppDataFolder);

                Process.Start(new ProcessStartInfo
                {
                    FileName = LoggerService.AppDataFolder,
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show("No se pudo abrir la carpeta de datos:\n" + ex.Message, "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private static string GetWindowXaml()
        {
            return @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='GameLauncher Neon'
        Width='1180' Height='740'
        MinWidth='900' MinHeight='580'
        WindowStartupLocation='CenterScreen'
        WindowStyle='None'
        ResizeMode='CanResizeWithGrip'
        Background='#090A10'
        Foreground='#F8FAFC'
        FontFamily='Segoe UI'>

    <Window.Resources>
        <Style x:Key='NeonPrimaryButton' TargetType='Button'>
            <Setter Property='Foreground' Value='#FFFFFF'/>
            <Setter Property='FontWeight' Value='SemiBold'/>
            <Setter Property='FontSize' Value='13'/>
            <Setter Property='Cursor' Value='Hand'/>
            <Setter Property='Padding' Value='16,9'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='Button'>
                        <Border x:Name='btnBorder' CornerRadius='8' Padding='{TemplateBinding Padding}' BorderThickness='1' BorderBrush='#A78BFA'>
                            <Border.Background>
                                <LinearGradientBrush StartPoint='0,0' EndPoint='1,1'>
                                    <GradientStop Color='#7C3AED' Offset='0'/>
                                    <GradientStop Color='#2563EB' Offset='1'/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <Border.Effect>
                                <DropShadowEffect x:Name='btnGlow' Color='#8B5CF6' BlurRadius='12' ShadowDepth='0' Opacity='0.35'/>
                            </Border.Effect>
                            <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property='IsMouseOver' Value='True'>
                                <Setter TargetName='btnBorder' Property='BorderBrush' Value='#06B6D4'/>
                                <Setter TargetName='btnGlow' Property='BlurRadius' Value='20'/>
                                <Setter TargetName='btnGlow' Property='Opacity' Value='0.75'/>
                                <Setter TargetName='btnGlow' Property='Color' Value='#06B6D4'/>
                            </Trigger>
                            <Trigger Property='IsPressed' Value='True'>
                                <Setter TargetName='btnBorder' Property='Opacity' Value='0.85'/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key='NeonSecondaryButton' TargetType='Button'>
            <Setter Property='Foreground' Value='#E2E8F0'/>
            <Setter Property='FontWeight' Value='Medium'/>
            <Setter Property='FontSize' Value='12.5'/>
            <Setter Property='Cursor' Value='Hand'/>
            <Setter Property='Padding' Value='12,7'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='Button'>
                        <Border x:Name='secBorder' Background='#191D30' CornerRadius='7' Padding='{TemplateBinding Padding}' BorderThickness='1' BorderBrush='#2E3656'>
                            <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property='IsMouseOver' Value='True'>
                                <Setter TargetName='secBorder' Property='Background' Value='#232842'/>
                                <Setter TargetName='secBorder' Property='BorderBrush' Value='#8B5CF6'/>
                                <Setter Property='Foreground' Value='#FFFFFF'/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key='TitleBarButton' TargetType='Button'>
            <Setter Property='Width' Value='42'/>
            <Setter Property='Height' Value='32'/>
            <Setter Property='Foreground' Value='#94A3B8'/>
            <Setter Property='Background' Value='Transparent'/>
            <Setter Property='BorderThickness' Value='0'/>
            <Setter Property='Cursor' Value='Hand'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='Button'>
                        <Border x:Name='tbBorder' Background='{TemplateBinding Background}' CornerRadius='6'>
                            <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property='IsMouseOver' Value='True'>
                                <Setter TargetName='tbBorder' Property='Background' Value='#232842'/>
                                <Setter Property='Foreground' Value='#FFFFFF'/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border x:Name='MainWindowBorder' Background='#090A10' BorderBrush='#2D2B52' BorderThickness='1.5' CornerRadius='10'>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height='54'/>
                <RowDefinition Height='*'/>
                <RowDefinition Height='32'/>
            </Grid.RowDefinitions>

            <!-- BARRA DE TÍTULO PERSONALIZADA -->
            <Border x:Name='TopTitleBar' Grid.Row='0' Background='#0C0E18' BorderBrush='#1E2238' BorderThickness='0,0,0,1' CornerRadius='10,10,0,0'>
                <Grid Margin='16,0,10,0'>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width='Auto'/>
                        <ColumnDefinition Width='*'/>
                        <ColumnDefinition Width='Auto'/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column='0' Orientation='Horizontal' VerticalAlignment='Center'>
                        <Border Width='34' Height='34' CornerRadius='8' BorderBrush='#06B6D4' BorderThickness='1.5' Margin='0,0,12,0'>
                            <Border.Background>
                                <LinearGradientBrush StartPoint='0,0' EndPoint='1,1'>
                                    <GradientStop Color='#1E1533' Offset='0'/>
                                    <GradientStop Color='#0F172A' Offset='1'/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <Border.Effect>
                                <DropShadowEffect Color='#8B5CF6' BlurRadius='10' ShadowDepth='0' Opacity='0.6'/>
                            </Border.Effect>
                            <Path Data='M10,7 L25,16 L10,25 L13,16 Z' Fill='#3B82F6' Stroke='#06B6D4' StrokeThickness='1.5' Stretch='Uniform' Margin='6'/>
                        </Border>
                        <StackPanel VerticalAlignment='Center'>
                            <StackPanel Orientation='Horizontal'>
                                <TextBlock Text='GAMELAUNCHER' FontWeight='Bold' FontSize='15' Foreground='#F8FAFC'/>
                                <TextBlock Text=' NEON' FontWeight='ExtraBold' FontSize='15' Foreground='#06B6D4' Margin='4,0,0,0'/>
                            </StackPanel>
                            <TextBlock Text='WINDOWS GAMING HUB' FontSize='9.5' Foreground='#64748B' FontWeight='SemiBold'/>
                        </StackPanel>
                    </StackPanel>

                    <Border Grid.Column='1' HorizontalAlignment='Center' VerticalAlignment='Center' Background='#131626' BorderBrush='#262B47' BorderThickness='1' CornerRadius='14' Padding='14,5'>
                        <StackPanel Orientation='Horizontal'>
                            <Ellipse Width='8' Height='8' Fill='#06B6D4' VerticalAlignment='Center' Margin='0,0,8,0'/>
                            <TextBlock x:Name='TopStatusText' Text='Biblioteca lista' FontSize='12' Foreground='#CBD5E1'/>
                        </StackPanel>
                    </Border>

                    <StackPanel Grid.Column='2' Orientation='Horizontal' VerticalAlignment='Center'>
                        <Button x:Name='MinimizeBtn' Style='{StaticResource TitleBarButton}' ToolTip='Minimizar'>
                            <TextBlock Text='—' FontSize='13' FontWeight='Bold'/>
                        </Button>
                        <Button x:Name='MaximizeBtn' Style='{StaticResource TitleBarButton}' ToolTip='Maximizar / Restaurar' Margin='4,0'>
                            <TextBlock x:Name='MaxRestoreIcon' Text='▢' FontSize='13'/>
                        </Button>
                        <Button x:Name='CloseBtn' Style='{StaticResource TitleBarButton}' ToolTip='Cerrar aplicación'>
                            <TextBlock Text='✕' FontSize='13' Foreground='#F87171'/>
                        </Button>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- CUERPO PRINCIPAL -->
            <Grid Grid.Row='1'>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width='235'/>
                    <ColumnDefinition Width='*'/>
                </Grid.ColumnDefinitions>

                <!-- BARRA LATERAL -->
                <Border Grid.Column='0' Background='#0E101A' BorderBrush='#1E2238' BorderThickness='0,0,1,0' Padding='14,18'>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height='Auto'/>
                            <RowDefinition Height='*'/>
                            <RowDefinition Height='Auto'/>
                        </Grid.RowDefinitions>

                        <Button x:Name='AddGameSidebarBtn' Grid.Row='0' Style='{StaticResource NeonPrimaryButton}' Height='42' Margin='0,0,0,22' ToolTip='Añadir un nuevo juego desde tu ordenador'>
                            <StackPanel Orientation='Horizontal'>
                                <TextBlock Text='＋' FontSize='15' FontWeight='Bold' Margin='0,0,8,0' VerticalAlignment='Center'/>
                                <TextBlock Text='AÑADIR JUEGO' VerticalAlignment='Center'/>
                            </StackPanel>
                        </Button>

                        <StackPanel Grid.Row='1'>
                            <TextBlock Text='NAVEGACIÓN' FontSize='10.5' FontWeight='Bold' Foreground='#64748B' Margin='8,0,0,8'/>

                            <Button x:Name='NavAllBtn' Style='{StaticResource NeonSecondaryButton}' HorizontalContentAlignment='Left' Margin='0,0,0,6' Padding='12,10'>
                                <StackPanel Orientation='Horizontal'>
                                    <TextBlock Text='❖' Foreground='#8B5CF6' Margin='0,0,10,0' FontSize='14'/>
                                    <TextBlock Text='Todos los Juegos'/>
                                </StackPanel>
                            </Button>

                            <Button x:Name='NavFavBtn' Style='{StaticResource NeonSecondaryButton}' HorizontalContentAlignment='Left' Margin='0,0,0,6' Padding='12,10'>
                                <StackPanel Orientation='Horizontal'>
                                    <TextBlock Text='★' Foreground='#F59E0B' Margin='0,0,10,0' FontSize='14'/>
                                    <TextBlock Text='Favoritos'/>
                                </StackPanel>
                            </Button>

                            <Button x:Name='NavHistoryBtn' Style='{StaticResource NeonSecondaryButton}' HorizontalContentAlignment='Left' Margin='0,0,0,6' Padding='12,10'>
                                <StackPanel Orientation='Horizontal'>
                                    <TextBlock Text='◷' Foreground='#06B6D4' Margin='0,0,10,0' FontSize='14'/>
                                    <TextBlock Text='Historial de Inicio'/>
                                </StackPanel>
                            </Button>

                            <Button x:Name='NavSettingsBtn' Style='{StaticResource NeonSecondaryButton}' HorizontalContentAlignment='Left' Margin='0,0,0,18' Padding='12,10'>
                                <StackPanel Orientation='Horizontal'>
                                    <TextBlock Text='⚙' Foreground='#3B82F6' Margin='0,0,10,0' FontSize='14'/>
                                    <TextBlock Text='Configuración y Datos'/>
                                </StackPanel>
                            </Button>

                            <TextBlock Text='HERRAMIENTAS RÁPIDAS' FontSize='10.5' FontWeight='Bold' Foreground='#64748B' Margin='8,6,0,8'/>

                            <Button x:Name='VerifyPathsBtn' Style='{StaticResource NeonSecondaryButton}' HorizontalContentAlignment='Left' Margin='0,0,0,6' Padding='12,9' ToolTip='Comprobar si todos los ejecutables existen en el disco'>
                                <StackPanel Orientation='Horizontal'>
                                    <TextBlock Text='↻' Foreground='#10B981' Margin='0,0,10,0' FontSize='14'/>
                                    <TextBlock Text='Verificar Rutas'/>
                                </StackPanel>
                            </Button>
                        </StackPanel>

                        <Border Grid.Row='2' Background='#141829' BorderBrush='#262C49' BorderThickness='1' CornerRadius='8' Padding='12'>
                            <StackPanel>
                                <TextBlock Text='ESTADO DE BIBLIOTECA' FontSize='10' FontWeight='Bold' Foreground='#8B5CF6' Margin='0,0,0,6'/>
                                <TextBlock x:Name='StatsTotalText' Text='Total: 0 juegos' FontSize='12' Foreground='#E2E8F0'/>
                                <TextBlock x:Name='StatsAvailableText' Text='Disponibles: 0' FontSize='11.5' Foreground='#10B981' Margin='0,2,0,0'/>
                                <TextBlock x:Name='StatsMissingText' Text='No disponibles: 0' FontSize='11.5' Foreground='#94A3B8' Margin='0,2,0,0'/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </Border>

                <!-- ÁREA PRINCIPAL -->
                <Grid Grid.Column='1' Margin='22,18,22,14'>

                    <!-- VISTA A: BIBLIOTECA -->
                    <Grid x:Name='LibraryView' Visibility='Visible'>
                        <Grid.RowDefinitions>
                            <RowDefinition Height='Auto'/>
                            <RowDefinition Height='*'/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row='0' Margin='0,0,0,18'>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width='*'/>
                                <ColumnDefinition Width='Auto'/>
                                <ColumnDefinition Width='Auto'/>
                            </Grid.ColumnDefinitions>

                            <Border Grid.Column='0' Background='#141726' BorderBrush='#2A3152' BorderThickness='1' CornerRadius='8' Padding='12,6' Margin='0,0,12,0'>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width='Auto'/>
                                        <ColumnDefinition Width='*'/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column='0' Text='🔍' Foreground='#64748B' VerticalAlignment='Center' Margin='0,0,8,0'/>
                                    <TextBox x:Name='SearchBox' Grid.Column='1' Background='Transparent' BorderThickness='0' Foreground='#F8FAFC' CaretBrush='#06B6D4' FontSize='13' VerticalContentAlignment='Center'/>
                                    <TextBlock x:Name='SearchPlaceholder' Grid.Column='1' Text='Buscar juegos por nombre...' Foreground='#64748B' FontSize='13' VerticalAlignment='Center' IsHitTestVisible='False'/>
                                </Grid>
                            </Border>

                            <Border Grid.Column='1' Background='#141726' BorderBrush='#2A3152' BorderThickness='1' CornerRadius='8' Padding='12,6' Margin='0,0,12,0' VerticalAlignment='Center'>
                                <CheckBox x:Name='OnlyAvailableCheck' Content='Solo disponibles' Foreground='#E2E8F0' VerticalContentAlignment='Center'/>
                            </Border>

                            <Border Grid.Column='2' Background='#141726' BorderBrush='#2A3152' BorderThickness='1' CornerRadius='8' Padding='10,4' VerticalAlignment='Center'>
                                <StackPanel Orientation='Horizontal' VerticalAlignment='Center'>
                                    <TextBlock Text='Ordenar:' Foreground='#94A3B8' FontSize='12' VerticalAlignment='Center' Margin='0,0,8,0'/>
                                    <ComboBox x:Name='SortComboBox' Width='155' SelectedIndex='0' VerticalContentAlignment='Center'>
                                        <ComboBoxItem Content='Nombre (A - Z)'/>
                                        <ComboBoxItem Content='Jugados recientemente'/>
                                        <ComboBoxItem Content='Más veces jugados'/>
                                        <ComboBoxItem Content='Disponibilidad'/>
                                    </ComboBox>
                                </StackPanel>
                            </Border>
                        </Grid>

                        <ScrollViewer Grid.Row='1' VerticalScrollBarVisibility='Auto'>
                            <Grid>
                                <ItemsControl x:Name='GamesItemsControl'>
                                    <ItemsControl.ItemsPanel>
                                        <ItemsPanelTemplate>
                                            <WrapPanel Orientation='Horizontal'/>
                                        </ItemsPanelTemplate>
                                    </ItemsControl.ItemsPanel>
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border Width='265' Margin='0,0,16,16' CornerRadius='12' Background='#141828' BorderThickness='1.5' Padding='14'>
                                                <Border.Style>
                                                    <Style TargetType='Border'>
                                                        <Setter Property='BorderBrush' Value='#252B48'/>
                                                        <Style.Triggers>
                                                            <Trigger Property='IsMouseOver' Value='True'>
                                                                <Setter Property='BorderBrush' Value='#06B6D4'/>
                                                                <Setter Property='Background' Value='#191E33'/>
                                                                <Setter Property='Effect'>
                                                                    <Setter.Value>
                                                                        <DropShadowEffect Color='#8B5CF6' BlurRadius='16' ShadowDepth='0' Opacity='0.45'/>
                                                                    </Setter.Value>
                                                                </Setter>
                                                            </Trigger>
                                                        </Style.Triggers>
                                                    </Style>
                                                </Border.Style>

                                                <StackPanel>
                                                    <Grid Height='115' Margin='0,0,0,12'>
                                                        <Border Background='#0D101C' CornerRadius='8' BorderBrush='#1F243D' BorderThickness='1'>
                                                            <Grid>
                                                                <Path Data='M6,12 L10,8 L22,8 L26,12 L25,22 L20,22 L18,19 L14,19 L12,22 L7,22 Z'
                                                                      Stroke='#3B82F6' StrokeThickness='1.5' Fill='#17203A'
                                                                      Width='54' Height='54' Stretch='Uniform' HorizontalAlignment='Center' VerticalAlignment='Center'/>
                                                                <Image Source='{Binding DisplayIcon}' Stretch='Uniform' MaxHeight='88' MaxWidth='200' HorizontalAlignment='Center' VerticalAlignment='Center' RenderOptions.BitmapScalingMode='HighQuality'/>
                                                            </Grid>
                                                        </Border>

                                                        <Border HorizontalAlignment='Left' VerticalAlignment='Top' Margin='8,8,0,0' CornerRadius='6' Padding='8,3' Background='#CC090A10' BorderThickness='1'>
                                                            <Border.Style>
                                                                <Style TargetType='Border'>
                                                                    <Setter Property='BorderBrush' Value='#10B981'/>
                                                                    <Style.Triggers>
                                                                        <DataTrigger Binding='{Binding IsAvailable}' Value='False'>
                                                                            <Setter Property='BorderBrush' Value='#EF4444'/>
                                                                        </DataTrigger>
                                                                    </Style.Triggers>
                                                                </Style>
                                                            </Border.Style>
                                                            <TextBlock Text='{Binding StatusText}' FontSize='10.5' FontWeight='SemiBold'>
                                                                <TextBlock.Style>
                                                                    <Style TargetType='TextBlock'>
                                                                        <Setter Property='Foreground' Value='#10B981'/>
                                                                        <Style.Triggers>
                                                                            <DataTrigger Binding='{Binding IsAvailable}' Value='False'>
                                                                                <Setter Property='Foreground' Value='#F87171'/>
                                                                            </DataTrigger>
                                                                        </Style.Triggers>
                                                                    </Style>
                                                                </TextBlock.Style>
                                                            </TextBlock>
                                                        </Border>

                                                        <Button Uid='Fav' Tag='{Binding}' HorizontalAlignment='Right' VerticalAlignment='Top' Margin='0,6,6,0' Style='{StaticResource NeonSecondaryButton}' Padding='7,3' ToolTip='Marcar o desmarcar como favorito'>
                                                            <TextBlock Text='{Binding FavoriteSymbol}' Foreground='#FBBF24' FontSize='14'/>
                                                        </Button>
                                                    </Grid>

                                                    <TextBlock Text='{Binding Title}' FontSize='15' FontWeight='Bold' Foreground='#F8FAFC' TextTrimming='CharacterEllipsis' ToolTip='{Binding Title}'/>
                                                    <TextBlock Text='{Binding ExecutablePath}' FontSize='11' Foreground='#64748B' TextTrimming='CharacterEllipsis' Margin='0,3,0,4' ToolTip='{Binding ExecutablePath}'/>
                                                    <TextBlock Text='{Binding LastPlayedText}' FontSize='11' Foreground='#94A3B8' Margin='0,0,0,12'/>

                                                    <Grid>
                                                        <Grid.ColumnDefinitions>
                                                            <ColumnDefinition Width='*'/>
                                                            <ColumnDefinition Width='Auto'/>
                                                            <ColumnDefinition Width='Auto'/>
                                                        </Grid.ColumnDefinitions>

                                                        <Button Grid.Column='0' Uid='Play' Tag='{Binding}' Style='{StaticResource NeonPrimaryButton}' Padding='10,8' Margin='0,0,6,0' ToolTip='Iniciar juego'>
                                                            <TextBlock Text='▶ JUGAR' FontWeight='Bold' FontSize='12.5'/>
                                                        </Button>

                                                        <Button Grid.Column='1' Uid='Edit' Tag='{Binding}' Style='{StaticResource NeonSecondaryButton}' Padding='9,8' Margin='0,0,6,0' ToolTip='Editar datos o actualizar ruta del ejecutable'>
                                                            <TextBlock Text='✎' FontSize='13'/>
                                                        </Button>

                                                        <Button Grid.Column='2' Uid='Remove' Tag='{Binding}' Style='{StaticResource NeonSecondaryButton}' Padding='9,8' ToolTip='Quitar de la biblioteca (no borra archivos del PC)'>
                                                            <TextBlock Text='🗑' Foreground='#F87171' FontSize='13'/>
                                                        </Button>
                                                    </Grid>
                                                </StackPanel>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>

                                <Border x:Name='EmptyStatePanel' Background='#111422' BorderBrush='#232946' BorderThickness='1' CornerRadius='12' Padding='40' HorizontalAlignment='Center' VerticalAlignment='Center' Visibility='Collapsed'>
                                    <StackPanel HorizontalAlignment='Center' MaxWidth='420'>
                                        <TextBlock Text='🎮' FontSize='42' HorizontalAlignment='Center' Margin='0,0,0,12'/>
                                        <TextBlock Text='Tu biblioteca está lista para empezar' FontSize='18' FontWeight='Bold' Foreground='#F8FAFC' HorizontalAlignment='Center' Margin='0,0,0,8'/>
                                        <TextBlock Text='Pulsa el botón «+ AÑADIR JUEGO» para seleccionar el archivo ejecutable (.exe) de cualquier juego instalado en tu ordenador.' FontSize='13' Foreground='#94A3B8' TextAlignment='Center' TextWrapping='Wrap' Margin='0,0,0,20'/>
                                        <Button x:Name='EmptyAddGameBtn' Style='{StaticResource NeonPrimaryButton}' HorizontalAlignment='Center' Padding='20,10' Content='＋ Añadir mi primer juego'/>
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </ScrollViewer>
                    </Grid>

                    <!-- VISTA B: HISTORIAL -->
                    <Grid x:Name='HistoryView' Visibility='Collapsed'>
                        <Grid.RowDefinitions>
                            <RowDefinition Height='Auto'/>
                            <RowDefinition Height='*'/>
                        </Grid.RowDefinitions>
                        <DockPanel Grid.Row='0' Margin='0,0,0,16'>
                            <StackPanel>
                                <TextBlock Text='HISTORIAL DE SESIONES' FontSize='18' FontWeight='Bold' Foreground='#F8FAFC'/>
                                <TextBlock Text='Registro cronológico de los últimos juegos iniciados desde GameLauncher.' FontSize='12.5' Foreground='#94A3B8'/>
                            </StackPanel>
                            <Button x:Name='ClearHistoryBtn' Style='{StaticResource NeonSecondaryButton}' HorizontalAlignment='Right' VerticalAlignment='Center' Content='Limpiar Historial'/>
                        </DockPanel>

                        <Border Grid.Row='1' Background='#131626' BorderBrush='#252B48' BorderThickness='1' CornerRadius='10' Padding='14'>
                            <ListBox x:Name='HistoryListBox' Background='Transparent' BorderThickness='0' Foreground='#E2E8F0' FontSize='13'/>
                        </Border>
                    </Grid>

                    <!-- VISTA C: CONFIGURACIÓN -->
                    <ScrollViewer x:Name='SettingsView' Visibility='Collapsed' VerticalScrollBarVisibility='Auto'>
                        <StackPanel MaxWidth='760' HorizontalAlignment='Left'>
                            <TextBlock Text='CONFIGURACIÓN Y GESTIÓN DE DATOS' FontSize='18' FontWeight='Bold' Foreground='#F8FAFC' Margin='0,0,0,6'/>
                            <TextBlock Text='Personaliza el comportamiento de GameLauncher y gestiona tus copias de seguridad locales.' FontSize='12.5' Foreground='#94A3B8' Margin='0,0,0,20'/>

                            <Border Background='#131626' BorderBrush='#252B48' BorderThickness='1' CornerRadius='10' Padding='18' Margin='0,0,0,16'>
                                <StackPanel>
                                    <TextBlock Text='COMPORTAMIENTO GENERAL' FontSize='13' FontWeight='Bold' Foreground='#06B6D4' Margin='0,0,0,12'/>
                                    <CheckBox x:Name='StartupWithWindowsCheck' Content='Iniciar GameLauncher automáticamente al iniciar sesión en Windows (Desactivado por defecto)' Foreground='#E2E8F0' Margin='0,0,0,10'/>
                                    <CheckBox x:Name='MinimizeOnLaunchCheck' Content='Minimizar GameLauncher automáticamente al abrir un juego' Foreground='#E2E8F0' Margin='0,0,0,10'/>
                                    <CheckBox x:Name='HighContrastBorderCheck' Content='Realzar bordes luminosos neón en la ventana principal' Foreground='#E2E8F0'/>
                                </StackPanel>
                            </Border>

                            <Border Background='#131626' BorderBrush='#252B48' BorderThickness='1' CornerRadius='10' Padding='18' Margin='0,0,0,16'>
                                <StackPanel>
                                    <TextBlock Text='PORTABILIDAD DE BIBLIOTECA (IMPORTAR / EXPORTAR)' FontSize='13' FontWeight='Bold' Foreground='#8B5CF6' Margin='0,0,0,6'/>
                                    <TextBlock Text='Guarda tu lista de juegos en un archivo JSON o cárgala en otro ordenador sin perder tu configuración.' FontSize='12' Foreground='#94A3B8' Margin='0,0,0,14'/>
                                    <StackPanel Orientation='Horizontal'>
                                        <Button x:Name='ExportLibraryBtn' Style='{StaticResource NeonPrimaryButton}' Content='Exportar Biblioteca (.json)' Margin='0,0,12,0'/>
                                        <Button x:Name='ImportLibraryBtn' Style='{StaticResource NeonSecondaryButton}' Content='Importar Biblioteca (.json)'/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <Border Background='#131626' BorderBrush='#252B48' BorderThickness='1' CornerRadius='10' Padding='18'>
                                <StackPanel>
                                    <TextBlock Text='PRIVACIDAD, ALMACENAMIENTO Y REGISTRO DE ERRORES' FontSize='13' FontWeight='Bold' Foreground='#10B981' Margin='0,0,0,6'/>
                                    <TextBlock Text='GameLauncher guarda los datos exclusivamente en tu perfil local (LocalAppData). No envía datos a Internet ni modifica los archivos originales de tus juegos.' FontSize='12' Foreground='#94A3B8' TextWrapping='Wrap' Margin='0,0,0,10'/>
                                    <TextBlock x:Name='LocalDataPathText' FontSize='11.5' Foreground='#CBD5E1' Margin='0,0,0,12'/>
                                    <StackPanel Orientation='Horizontal'>
                                        <Button x:Name='OpenDataFolderBtn' Style='{StaticResource NeonSecondaryButton}' Content='Abrir Carpeta de Datos y Logs'/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </Grid>

            <!-- BARRA DE ESTADO INFERIOR -->
            <Border Grid.Row='2' Background='#0C0E18' BorderBrush='#1E2238' BorderThickness='0,1,0,0' CornerRadius='0,0,10,10' Padding='16,0'>
                <DockPanel VerticalAlignment='Center'>
                    <TextBlock x:Name='FooterStatusText' Text='Listo. Los archivos originales de los juegos nunca son modificados.' FontSize='11.5' Foreground='#64748B'/>
                    <TextBlock Text='v1.0.0 • Windows x64 • Almacenamiento Seguro LocalAppData' FontSize='11' Foreground='#475569' HorizontalAlignment='Right'/>
                </DockPanel>
            </Border>

            <!-- MODAL AÑADIR / EDITAR JUEGO -->
            <Border x:Name='GameModalOverlay' Grid.Row='0' Grid.RowSpan='3' Background='#CC06070B' Visibility='Collapsed' CornerRadius='10'>
                <Border Width='520' VerticalAlignment='Center' HorizontalAlignment='Center' Background='#131728' BorderBrush='#8B5CF6' BorderThickness='1.5' CornerRadius='12' Padding='24'>
                    <Border.Effect>
                        <DropShadowEffect Color='#000000' BlurRadius='35' ShadowDepth='0' Opacity='0.8'/>
                    </Border.Effect>
                    <StackPanel>
                        <TextBlock x:Name='ModalHeaderTitle' Text='AÑADIR JUEGO A LA BIBLIOTECA' FontSize='16' FontWeight='Bold' Foreground='#06B6D4' Margin='0,0,0,16'/>

                        <TextBlock Text='Archivo ejecutable del juego (.exe) *' FontSize='12' Foreground='#CBD5E1' Margin='0,0,0,6'/>
                        <Grid Margin='0,0,0,14'>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width='*'/>
                                <ColumnDefinition Width='Auto'/>
                            </Grid.ColumnDefinitions>
                            <Border Grid.Column='0' Background='#0B0D17' BorderBrush='#2E3656' BorderThickness='1' CornerRadius='6' Padding='8,6' Margin='0,0,8,0'>
                                <TextBox x:Name='ModalExePathBox' Background='Transparent' BorderThickness='0' Foreground='#F8FAFC' CaretBrush='#06B6D4' FontSize='12.5'/>
                            </Border>
                            <Button x:Name='BrowseExeBtn' Grid.Column='1' Style='{StaticResource NeonSecondaryButton}' Content='Examinar .exe...'/>
                        </Grid>

                        <TextBlock Text='Nombre personalizado del juego *' FontSize='12' Foreground='#CBD5E1' Margin='0,0,0,6'/>
                        <Border Background='#0B0D17' BorderBrush='#2E3656' BorderThickness='1' CornerRadius='6' Padding='8,6' Margin='0,0,0,14'>
                            <TextBox x:Name='ModalTitleBox' Background='Transparent' BorderThickness='0' Foreground='#F8FAFC' CaretBrush='#06B6D4' FontSize='13'/>
                        </Border>

                        <TextBlock Text='Imagen o carátula personalizada (Opcional - PNG/JPG)' FontSize='12' Foreground='#CBD5E1' Margin='0,0,0,6'/>
                        <Grid Margin='0,0,0,14'>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width='*'/>
                                <ColumnDefinition Width='Auto'/>
                            </Grid.ColumnDefinitions>
                            <Border Grid.Column='0' Background='#0B0D17' BorderBrush='#2E3656' BorderThickness='1' CornerRadius='6' Padding='8,6' Margin='0,0,8,0'>
                                <TextBox x:Name='ModalCoverPathBox' Background='Transparent' BorderThickness='0' Foreground='#F8FAFC' CaretBrush='#06B6D4' FontSize='12'/>
                            </Border>
                            <Button x:Name='BrowseCoverBtn' Grid.Column='1' Style='{StaticResource NeonSecondaryButton}' Content='Elegir imagen...'/>
                        </Grid>

                        <TextBlock Text='Parámetros de lanzamiento opcionales (Avanzado)' FontSize='12' Foreground='#CBD5E1' Margin='0,0,0,6'/>
                        <Border Background='#0B0D17' BorderBrush='#2E3656' BorderThickness='1' CornerRadius='6' Padding='8,6' Margin='0,0,0,22'>
                            <TextBox x:Name='ModalArgsBox' Background='Transparent' BorderThickness='0' Foreground='#F8FAFC' CaretBrush='#06B6D4' FontSize='12'/>
                        </Border>

                        <StackPanel Orientation='Horizontal' HorizontalAlignment='Right'>
                            <Button x:Name='CancelModalBtn' Style='{StaticResource NeonSecondaryButton}' Content='Cancelar' Margin='0,0,10,0' Padding='16,8'/>
                            <Button x:Name='SaveModalBtn' Style='{StaticResource NeonPrimaryButton}' Content='Guardar Juego' Padding='20,8'/>
                        </StackPanel>
                    </StackPanel>
                </Border>
            </Border>
        </Grid>
    </Border>
</Window>";
        }
    }

    public static class Program
    {
        [STAThread]
        public static void Main()
        {
            LoggerService.Info("Iniciando GameLauncher Neon...");
            Application app = new Application();
            app.DispatcherUnhandledException += (s, e) =>
            {
                LoggerService.Error("Excepción no controlada en la interfaz", e.Exception);
                MessageBox.Show(
                    "Se produjo un error inesperado:\n" + e.Exception.Message + "\n\nEl detalle se ha registrado en logs\\app.log.",
                    "Error en GameLauncher Neon",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
                e.Handled = true;
            };

            MainWindowController controller = new MainWindowController();
            app.Run(controller.MainWindow);
        }
    }
}
