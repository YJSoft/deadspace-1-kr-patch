mod install;
mod vpatch;

use fltk::{
    app,
    button::Button,
    dialog,
    enums::{Align, Color, Font, FrameType},
    frame::Frame,
    input::Input,
    output::Output,
    prelude::*,
    text::{TextBuffer, TextDisplay},
    window::Window,
};
use install::{Resources, LAUNCH_OPTION, VERSION};
use std::{env, path::PathBuf, thread};

#[derive(Clone, Debug)]
enum UiMessage {
    Log(String),
    Finished(Result<String, String>),
}

fn main() {
    if handle_command_line() {
        return;
    }

    let resources = match Resources::discover() {
        Ok(resources) => resources,
        Err(error) => {
            eprintln!("설치기 구성 오류: {error:#}");
            return;
        }
    };

    let app = app::App::default().with_scheme(app::Scheme::Gtk);
    if let Ok(name) = Font::load_font(resources.root.join("fonts/NanumBarunGothic.ttf")) {
        Font::set_font(Font::Helvetica, &name);
        Font::set_font(Font::HelveticaBold, &name);
    }
    app::background(27, 30, 34);
    app::background2(38, 42, 47);
    app::foreground(235, 238, 241);
    app::set_selection_color(216, 107, 44);

    let mut window = Window::new(100, 100, 780, 610, None);
    window.set_label(&format!("Dead Space 1 한국어 개선 패치 {VERSION}"));
    window.set_color(Color::from_rgb(27, 30, 34));

    let mut title = Frame::new(28, 22, 724, 40, None);
    title.set_label(&format!("Dead Space 1 한국어 개선 패치  {VERSION}"));
    title.set_label_size(25);
    title.set_label_color(Color::from_rgb(235, 132, 65));
    title.set_label_font(Font::HelveticaBold);
    title.set_align(Align::Left | Align::Inside);

    let mut intro = Frame::new(
        28,
        65,
        724,
        55,
        "Steam/Proton판 Dead Space (2008)에 한국어 패치를 설치합니다.\n게임을 완전히 종료한 뒤 설치 폴더를 확인하십시오. 관리자 권한은 필요하지 않습니다.",
    );
    intro.set_label_size(15);
    intro.set_label_color(Color::from_rgb(205, 210, 216));
    intro.set_align(Align::Left | Align::Inside | Align::Wrap);

    let mut path_label = Frame::new(28, 128, 724, 24, "Dead Space 설치 폴더");
    path_label.set_label_size(15);
    path_label.set_align(Align::Left | Align::Inside);

    let detected = install::detect_game_dirs();
    let initial_path = detected
        .first()
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_default();
    let mut path_input = Input::new(28, 156, 620, 38, "");
    path_input.set_value(&initial_path);
    path_input.set_text_size(14);
    path_input.set_color(Color::from_rgb(43, 48, 54));
    path_input.set_text_color(Color::White);

    let mut browse = Button::new(658, 156, 94, 38, "찾아보기");
    browse.set_color(Color::from_rgb(67, 73, 80));
    browse.set_label_color(Color::White);
    browse.set_label_size(14);

    let detected_text = if detected.is_empty() {
        "Steam 설치 경로를 자동으로 찾지 못했습니다. 찾아보기로 Dead Space.exe가 있는 폴더를 선택하십시오."
    } else {
        "Steam 라이브러리에서 게임을 찾았습니다. 경로가 맞으면 바로 설치할 수 있습니다."
    };
    let mut detected_frame = Frame::new(28, 198, 724, 26, detected_text);
    detected_frame.set_label_size(13);
    detected_frame.set_label_color(Color::from_rgb(155, 164, 174));
    detected_frame.set_align(Align::Left | Align::Inside | Align::Wrap);

    let mut log_display = TextDisplay::new(28, 232, 724, 150, "");
    log_display.set_frame(FrameType::FlatBox);
    log_display.set_color(Color::from_rgb(18, 20, 23));
    log_display.set_text_color(Color::from_rgb(214, 219, 224));
    log_display.set_text_size(14);
    let mut log_buffer = TextBuffer::default();
    log_buffer.set_text("준비되었습니다. 설치하면 지원 원본 검사와 백업을 먼저 수행합니다.\n");
    log_display.set_buffer(log_buffer.clone());

    let mut install_button = Button::new(28, 398, 235, 42, "설치 / 업데이트");
    install_button.set_color(Color::from_rgb(202, 91, 35));
    install_button.set_label_color(Color::White);
    install_button.set_label_size(16);
    let mut uninstall_button = Button::new(275, 398, 235, 42, "원본 복원 / 패치 제거");
    uninstall_button.set_color(Color::from_rgb(71, 77, 84));
    uninstall_button.set_label_color(Color::White);
    uninstall_button.set_label_size(15);
    let mut close_button = Button::new(522, 398, 230, 42, "닫기");
    close_button.set_color(Color::from_rgb(55, 60, 66));
    close_button.set_label_color(Color::White);

    let mut option_title = Frame::new(28, 456, 724, 26, "Steam 실행 옵션 — 설치 후 반드시 적용");
    option_title.set_label_size(16);
    option_title.set_label_font(Font::HelveticaBold);
    option_title.set_label_color(Color::from_rgb(235, 132, 65));
    option_title.set_align(Align::Left | Align::Inside);

    let mut option_output = Output::new(28, 488, 590, 38, "");
    option_output.set_value(LAUNCH_OPTION);
    option_output.set_text_size(14);
    option_output.set_color(Color::from_rgb(43, 48, 54));
    option_output.set_text_color(Color::White);
    let mut copy_button = Button::new(630, 488, 122, 38, "옵션 복사");
    copy_button.set_color(Color::from_rgb(202, 91, 35));
    copy_button.set_label_color(Color::White);

    let mut option_help = Frame::new(
        28,
        530,
        724,
        54,
        "Steam → 라이브러리 → Dead Space → 속성 → 일반 → 실행 옵션에 붙여넣으십시오.\n이 옵션이 없으면 Proton이 패치 DLL 대신 내장 DLL을 사용해 한글이 깨질 수 있습니다.",
    );
    option_help.set_label_size(13);
    option_help.set_label_color(Color::from_rgb(184, 191, 199));
    option_help.set_align(Align::Left | Align::Inside | Align::Wrap);

    window.end();
    window.make_resizable(false);
    window.show();

    {
        let mut path_input = path_input.clone();
        browse.set_callback(move |_| {
            let mut chooser =
                dialog::NativeFileChooser::new(dialog::NativeFileChooserType::BrowseDir);
            chooser.set_title("Dead Space.exe가 있는 설치 폴더 선택");
            chooser.show();
            let selected = chooser.filename();
            if !selected.as_os_str().is_empty() {
                path_input.set_value(&selected.to_string_lossy());
            }
        });
    }

    copy_button.set_callback(move |button| {
        app::copy(LAUNCH_OPTION);
        button.set_label("복사됨");
    });
    close_button.set_callback(|_| app::quit());

    let (sender, receiver) = app::channel::<UiMessage>();
    {
        let path_input = path_input.clone();
        let resources = resources.clone();
        let install_sender = sender;
        install_button.set_callback(move |button| {
            button.deactivate();
            let game = PathBuf::from(path_input.value());
            let resources = resources.clone();
            let sender = install_sender;
            thread::spawn(move || {
                let result = install::install(&game, &resources, |line| {
                    sender.send(UiMessage::Log(line.to_string()));
                });
                let result = result
                    .map(|_| "한국어 패치 설치가 완료되었습니다. 실행 옵션을 복사해 Steam에 적용하십시오.".to_string())
                    .map_err(|error| format!("설치를 완료하지 못했습니다.\n{error:#}"));
                sender.send(UiMessage::Finished(result));
            });
        });
    }
    {
        let path_input = path_input.clone();
        let uninstall_sender = sender;
        uninstall_button.set_callback(move |button| {
            button.deactivate();
            let game = PathBuf::from(path_input.value());
            let sender = uninstall_sender;
            thread::spawn(move || {
                let result = install::uninstall(&game, |line| {
                    sender.send(UiMessage::Log(line.to_string()));
                });
                let result = result
                    .map(|_| {
                        "원본 파일을 복원하고 패치를 제거했습니다. DS1K_Backup 폴더는 유지됩니다."
                            .to_string()
                    })
                    .map_err(|error| format!("패치를 제거하지 못했습니다.\n{error:#}"));
                sender.send(UiMessage::Finished(result));
            });
        });
    }

    while app.wait() {
        if let Some(message) = receiver.recv() {
            match message {
                UiMessage::Log(line) => {
                    log_buffer.append(&format!("{line}\n"));
                    log_display.scroll(log_buffer.count_lines(0, log_buffer.length()), 0);
                    install_button.deactivate();
                    uninstall_button.deactivate();
                    browse.deactivate();
                }
                UiMessage::Finished(result) => {
                    install_button.activate();
                    uninstall_button.activate();
                    browse.activate();
                    match result {
                        Ok(message) => {
                            log_buffer.append(&format!("{message}\n"));
                            dialog::message_default(&message);
                        }
                        Err(message) => {
                            log_buffer.append(&format!("오류: {message}\n"));
                            dialog::alert_default(&message);
                        }
                    }
                    log_display.scroll(log_buffer.count_lines(0, log_buffer.length()), 0);
                }
            }
        }
    }
}

fn handle_command_line() -> bool {
    let args = env::args().collect::<Vec<_>>();
    if args.len() == 1 {
        return false;
    }
    match args[1].as_str() {
        "--version" => {
            println!("Dead Space 1 KR Linux Installer {VERSION}");
            true
        }
        "--detect" => {
            for path in install::detect_game_dirs() {
                println!("{}", path.display());
            }
            true
        }
        "--verify-resources" => match Resources::discover() {
            Ok(resources) => {
                if let Err(error) = resources.verify() {
                    eprintln!("{error:#}");
                    std::process::exit(2);
                }
                println!("OK {}", resources.root.display());
                true
            }
            Err(error) => {
                eprintln!("{error:#}");
                std::process::exit(2);
            }
        },
        "--install" if args.len() == 3 => {
            let resources = Resources::discover().unwrap_or_else(|error| {
                eprintln!("{error:#}");
                std::process::exit(2);
            });
            install::install(PathBuf::from(&args[2]).as_path(), &resources, |line| {
                println!("{line}")
            })
            .unwrap_or_else(|error| {
                eprintln!("{error:#}");
                std::process::exit(2);
            });
            true
        }
        "--uninstall" if args.len() == 3 => {
            install::uninstall(PathBuf::from(&args[2]).as_path(), |line| println!("{line}"))
                .unwrap_or_else(|error| {
                    eprintln!("{error:#}");
                    std::process::exit(2);
                });
            true
        }
        _ => false,
    }
}
